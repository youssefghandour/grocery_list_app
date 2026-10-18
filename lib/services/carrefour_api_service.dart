import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class CarrefourProduct {
  const CarrefourProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.url,
    this.brand,
    this.oldPrice,
    this.lastSeen,
  });

  final String id;
  final String name;
  final String? brand;
  final double? price;
  final double? oldPrice;
  final String? url;
  final String? lastSeen;

  factory CarrefourProduct.fromJson(Map<String, dynamic> json) {
    double? asDouble(dynamic value) => value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');

    return CarrefourProduct(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Carrefour product',
      brand: json['brand']?.toString(),
      price: asDouble(json['price']),
      oldPrice: asDouble(json['old_price']),
      url: json['url']?.toString(),
      lastSeen: json['last_seen']?.toString(),
    );
  }
}

class CarrefourApiException implements Exception {
  const CarrefourApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CarrefourApiService {
  CarrefourApiService({http.Client? client, FirebaseAuth? auth})
    : _client = client ?? http.Client(),
      _auth = auth ?? FirebaseAuth.instance;

  final http.Client _client;
  final FirebaseAuth _auth;

  static const _configuredBaseUrl = String.fromEnvironment(
    'CARREFOUR_API_BASE_URL',
  );
  static const _firebaseFunctionsBaseUrl =
      'https://carrefourapi-2a7u7yjvva-ew.a.run.app';

  String get _baseUrl {
    if (_configuredBaseUrl.isNotEmpty) {
      return _configuredBaseUrl.replaceFirst(RegExp(r'/$'), '');
    }
    return _firebaseFunctionsBaseUrl;
  }

  Future<List<CarrefourProduct>> search(String query) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const CarrefourApiException('Sign in to search Carrefour prices.');
    }
    final idToken = await user.getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw const CarrefourApiException('Could not authenticate price search.');
    }
    final uri = Uri.parse('$_baseUrl/products').replace(
      queryParameters: {'q': query.trim(), 'sort': 'price_asc', 'limit': '100'},
    );

    final response = await _client
        .get(
          uri,
          headers: {'Accept': 'application/json', 'Authorization': 'Bearer $idToken'},
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) {
      throw CarrefourApiException(
        'Carrefour API returned ${response.statusCode}.',
      );
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic> || decoded['items'] is! List) {
      throw const CarrefourApiException('Carrefour API response was invalid.');
    }

    return (decoded['items'] as List)
        .whereType<Map<String, dynamic>>()
        .map(CarrefourProduct.fromJson)
        .toList();
  }

  Future<List<CarrefourProduct>> searchMatches(String query) async {
    final queryTokens = _tokens(query);
    if (queryTokens.isEmpty) return const [];
    final products = await search(query);
    return products.where((product) {
      final productTokens = _tokens('${product.name} ${product.brand ?? ''}');
      return queryTokens.every(productTokens.contains) &&
          _isPlausibleProduct(query, productTokens);
    }).toList();
  }

  Future<CarrefourProduct?> findProductById({
    required String query,
    required String productId,
  }) async {
    if (productId.isEmpty) return null;
    final products = await searchMatches(query);
    for (final product in products) {
      if (product.id == productId) return product;
    }
    return null;
  }

  double? priceForUnit(CarrefourProduct product, String unit) {
    final price = product.price;
    if (price == null || !price.isFinite || price <= 0) return null;
    final packSize = _packSizeInUnit(product.name, unit);
    if (_requiresPackSize(unit) && packSize == null) return null;
    return packSize == null ? price : price / packSize;
  }

  /// Finds a conservative Carrefour estimate expressed in the grocery item's unit.
  /// For weight/volume items, only products with a readable pack size are used.
  Future<double?> estimateUnitPrice({
    required String itemName,
    required String unit,
  }) async {
    final queryTokens = _tokens(itemName);
    if (queryTokens.isEmpty) return null;

    final products = await searchMatches(itemName);
    // A single broad word ("milk", "oil", or a brand name) is not enough to
    // identify a grocery product safely. Leave it for the user's manual picker.
    final confidence = _queryConfidence(queryTokens);
    if (confidence < _automaticPriceConfidenceThreshold) return null;

    final candidates =
        <({double unitPrice, int productPreference, String? packSize})>[];
    for (final product in products) {
      final unitPrice = priceForUnit(product, unit);
      if (unitPrice == null) continue;

      final productTokens = _tokens('${product.name} ${product.brand ?? ''}');

      candidates.add((
        unitPrice: unitPrice,
        productPreference: _milkPreference(itemName, productTokens),
        packSize: _packSizeDescriptor(product.name),
      ));
    }

    if (candidates.isEmpty) return null;

    // For piece/pack prices, products in different pack sizes are not
    // comparable. Don't silently choose the cheapest one when the list item
    // doesn't say which size the user meant. Weight/volume items are normalized
    // above, so different pack sizes remain comparable for those units.
    if (!_requiresPackSize(unit)) {
      final knownPackSizes = candidates
          .map((candidate) => candidate.packSize)
          .whereType<String>()
          .toSet();
      final hasUnknownPackSize = candidates.any(
        (candidate) => candidate.packSize == null,
      );
      if (knownPackSizes.length > 1 ||
          (knownPackSizes.isNotEmpty && hasUnknownPackSize)) {
        return null;
      }
    }

    candidates.sort((a, b) {
      final preferenceOrder = b.productPreference.compareTo(
        a.productPreference,
      );
      if (preferenceOrder != 0) return preferenceOrder;
      return a.unitPrice.compareTo(b.unitPrice);
    });
    return candidates.first.unitPrice;
  }

  static const double _automaticPriceConfidenceThreshold = 0.72;

  /// Scores how specifically the list item names a product. Search results
  /// already have to contain every query token; this score prevents broad,
  /// one-word searches from becoming automatic prices.
  static double _queryConfidence(Set<String> queryTokens) {
    final specificity = queryTokens.length;
    if (specificity < 2) return 0.0;
    return (0.50 + 0.12 * specificity).clamp(0.0, 1.0).toDouble();
  }

  static Set<String> _tokens(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toSet();

  static bool _isPlausibleProduct(String itemName, Set<String> productTokens) {
    final queryTokens = _tokens(itemName);
    if (queryTokens.length == 1 && queryTokens.contains('milk')) {
      const nonDrinkingMilkTerms = {
        'soap',
        'hand',
        'chocolate',
        'cocoa',
        'strawberry',
        'banana',
        'caramel',
        'vanilla',
        'flavored',
        'cookies',
        'dates',
        'barista',
        'foam',
        'buttermilk',
        'rayeb',
        'labneh',
        'powder',
        'formula',
        'almond',
        'soya',
        'soy',
        'coconut',
        'oat',
      };
      if (productTokens.any(nonDrinkingMilkTerms.contains)) return false;
    }
    return true;
  }

  static int _milkPreference(String itemName, Set<String> productTokens) {
    final queryTokens = _tokens(itemName);
    if (queryTokens.length != 1 || !queryTokens.contains('milk')) return 0;
    if (productTokens.contains('whole') ||
        (productTokens.contains('full') && productTokens.contains('cream')) ||
        (productTokens.contains('full') && productTokens.contains('fat'))) {
      return 1;
    }
    return 0;
  }

  static bool _requiresPackSize(String unit) =>
      const {'kg', 'g', 'l', 'ml'}.contains(unit.trim().toLowerCase());

  static String? _packSizeDescriptor(String productName) {
    final match = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(kilograms?|kgs?|kg|grams?|g|litres?|liters?|ml|millilitres?|milliliters?|l)\b',
      caseSensitive: false,
    ).firstMatch(productName);
    if (match == null) return null;

    final amount = double.tryParse(match.group(1)!.replaceAll(',', '.'));
    final packUnit = match.group(2)!.toLowerCase();
    if (amount == null || amount <= 0) return null;

    if (packUnit.startsWith('kg') || packUnit.startsWith('kilo')) {
      return 'g:${(amount * 1000).toStringAsFixed(3)}';
    }
    if (packUnit.startsWith('g')) return 'g:${amount.toStringAsFixed(3)}';
    if (packUnit == 'l' || packUnit.startsWith('lit')) {
      return 'ml:${(amount * 1000).toStringAsFixed(3)}';
    }
    if (packUnit == 'ml' || packUnit.startsWith('milli')) {
      return 'ml:${amount.toStringAsFixed(3)}';
    }
    return null;
  }

  static double? _packSizeInUnit(String productName, String unit) {
    final normalizedUnit = unit.trim().toLowerCase();
    final match = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(kilograms?|kgs?|kg|grams?|g|litres?|liters?|ml|millilitres?|milliliters?|l)\b',
      caseSensitive: false,
    ).firstMatch(productName);
    if (match == null) return null;

    final amount = double.tryParse(match.group(1)!.replaceAll(',', '.'));
    final packUnit = match.group(2)!.toLowerCase();
    if (amount == null || amount <= 0) return null;

    final sizeInGrams = packUnit.startsWith('kg') || packUnit.startsWith('kilo')
        ? amount * 1000
        : packUnit.startsWith('g')
        ? amount
        : null;
    final sizeInMl = packUnit == 'l' || packUnit.startsWith('lit')
        ? amount * 1000
        : packUnit == 'ml' || packUnit.startsWith('milli')
        ? amount
        : null;

    return switch (normalizedUnit) {
      'kg' => sizeInGrams == null ? null : sizeInGrams / 1000,
      'g' => sizeInGrams,
      'l' => sizeInMl == null ? null : sizeInMl / 1000,
      'ml' => sizeInMl,
      _ => null,
    };
  }

  void close() => _client.close();
}
