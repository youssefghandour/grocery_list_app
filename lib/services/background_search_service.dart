import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product_cache_model.dart';

final backgroundSearchServiceProvider = Provider((ref) => BackgroundSearchService());

class BackgroundSearchService {
  BackgroundSearchService({FirebaseFirestore? firestore, FirebaseFunctions? functions})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _cache =>
      _firestore.collection('product_cache');

  /// Calls your Firebase Cloud Function to find real deals and brochures.
  Future<void> searchAndCache(String itemName) async {
    final term = itemName.trim().toLowerCase();
    if (term.isEmpty) return;

    try {
      // 1. Check for fresh cache (< 24 hours)
      final doc = await _cache.doc(term).get();
      if (doc.exists) {
        final match = ProductMatch.fromFirestore(doc);
        if (DateTime.now().difference(match.lastUpdated).inHours < 24) {
          debugPrint('SEARCH: Using cached data for "$term".');
          return;
        }
      }

      debugPrint('SEARCH: Calling Cloud Function for real-time Egypt deals: "$term"...');

      // 2. Call the Firebase Function
      final HttpsCallable callable = _functions.httpsCallable(
        'searchProductDeals',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final results = await callable.call(<String, dynamic>{
        'query': term,
      });

      final data = results.data;
      if (data == null) return;

      // 3. Map the real deals from the API
      final List<StoreLink> links = (data['deals'] as List).map((d) {
        return StoreLink(
          storeName: d['storeName'] ?? 'Local Store',
          price: (d['price'] as num?)?.toDouble() ?? 0.0,
          url: d['url'] ?? '',
          brochureUrl: d['image'], // The flyer/image from your API
          dateFound: d['dateFound'],
          isLowestPrice: false, // We will calculate this below
        );
      }).toList();

      if (links.isEmpty) return;

      // Find lowest price
      links.sort((a, b) => a.price.compareTo(b.price));
      final lowestPrice = links.first.price;
      final finalLinks = links.map((l) => l.copyWith(isLowestPrice: l.price == lowestPrice)).toList();

      // 4. Cache everything to Firestore
      final match = ProductMatch(
        id: term,
        searchTerm: term,
        displayName: data['name'] ?? itemName,
        brand: data['brand'] ?? '',
        imageUrl: data['image'] ?? '',
        lastUpdated: DateTime.now(),
        links: finalLinks,
      );

      await _cache.doc(term).set(match.toFirestore());
      debugPrint('SEARCH: Successfully cached real deals for "$term".');
    } catch (e) {
      debugPrint('SEARCH: Cloud Function failed: $e');
    }
  }
}

// Add copyWith to StoreLink in models to support the logic above
extension StoreLinkExtension on StoreLink {
  StoreLink copyWith({bool? isLowestPrice}) {
    return StoreLink(
      storeName: storeName,
      price: price,
      url: url,
      isLowestPrice: isLowestPrice ?? this.isLowestPrice,
      isSale: isSale,
      originalPrice: originalPrice,
      brochureUrl: brochureUrl,
      dateFound: dateFound,
    );
  }
}
