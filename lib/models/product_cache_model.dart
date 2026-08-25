import 'package:cloud_firestore/cloud_firestore.dart';

class StoreLink {
  const StoreLink({
    required this.storeName,
    required this.price,
    required this.url,
    this.isLowestPrice = false,
    this.isSale = false,
    this.originalPrice,
    this.brochureUrl,
    this.dateFound,
  });

  final String storeName;
  final double price;
  final double? originalPrice;
  final String url;
  final bool isLowestPrice;
  final bool isSale;
  final String? brochureUrl;
  final String? dateFound;

  factory StoreLink.fromMap(Map<String, dynamic> map) {
    return StoreLink(
      storeName: map['storeName'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      originalPrice: (map['originalPrice'] as num?)?.toDouble(),
      url: map['url'] as String? ?? '',
      isLowestPrice: map['isLowestPrice'] as bool? ?? false,
      isSale: map['isSale'] as bool? ?? false,
      brochureUrl: map['brochureUrl'] as String?,
      dateFound: map['dateFound'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'storeName': storeName,
      'price': price,
      'originalPrice': originalPrice,
      'url': url,
      'isLowestPrice': isLowestPrice,
      'isSale': isSale,
      'brochureUrl': brochureUrl,
      'dateFound': dateFound,
    };
  }
}

class ProductMatch {
  const ProductMatch({
    required this.id,
    required this.searchTerm,
    required this.displayName,
    required this.brand,
    required this.imageUrl,
    required this.lastUpdated,
    required this.links,
  });

  final String id;
  final String searchTerm;
  final String displayName;
  final String brand;
  final String imageUrl;
  final DateTime lastUpdated;
  final List<StoreLink> links;

  factory ProductMatch.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return ProductMatch(
      id: doc.id,
      searchTerm: data['searchTerm'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      brand: data['brand'] as String? ?? '',
      imageUrl: data['imageUrl'] as String? ?? '',
      lastUpdated: (data['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now(),
      links: (data['links'] as List<dynamic>? ?? [])
          .map((l) => StoreLink.fromMap(l as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'searchTerm': searchTerm,
      'displayName': displayName,
      'brand': brand,
      'imageUrl': imageUrl,
      'lastUpdated': Timestamp.fromDate(lastUpdated),
      'links': links.map((l) => l.toMap()).toList(),
    };
  }
}
