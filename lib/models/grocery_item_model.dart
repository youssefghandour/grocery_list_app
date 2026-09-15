import 'package:cloud_firestore/cloud_firestore.dart';

class GroceryItem {
  const GroceryItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.isChecked,
    required this.addedBy,
    required this.createdAt,
    required this.updatedAt,
    this.category = 'Other',
    this.unit = 'pcs',
    this.price = 0.0,
    this.isDeal = false,
    this.originalPrice,
    this.store,
    this.imageUrl,
  });

  final String id;
  final String name;
  final String quantity;
  final bool isChecked;
  final String addedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String category;
  final String unit;
  final double price;
  final bool isDeal;
  final double? originalPrice;
  final String? store;
  final String? imageUrl;

  factory GroceryItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return GroceryItem(
      id: doc.id,
      name: data['name'] as String? ?? '',
      quantity: data['quantity'] as String? ?? '1.0',
      isChecked: data['isChecked'] as bool? ?? false,
      addedBy: data['addedBy'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      category: data['category'] as String? ?? 'Other',
      unit: data['unit'] as String? ?? 'pcs',
      price: (data['price'] as num?)?.toDouble() ?? 0.0,
      isDeal: data['isDeal'] as bool? ?? false,
      originalPrice: (data['originalPrice'] as num?)?.toDouble(),
      store: data['store'] as String?,
      imageUrl: data['imageUrl'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'quantity': quantity,
      'isChecked': isChecked,
      'addedBy': addedBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'category': category,
      'unit': unit,
      'price': price,
      'isDeal': isDeal,
      if (originalPrice != null) 'originalPrice': originalPrice,
      if (store != null) 'store': store,
      if (imageUrl != null) 'imageUrl': imageUrl,
    };
  }

  GroceryItem copyWith({
    String? name,
    String? quantity,
    bool? isChecked,
    DateTime? updatedAt,
    String? category,
    String? unit,
    double? price,
    bool? isDeal,
    double? originalPrice,
    String? store,
    String? imageUrl,
  }) {
    return GroceryItem(
      id: id,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      isChecked: isChecked ?? this.isChecked,
      addedBy: addedBy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      category: category ?? this.category,
      unit: unit ?? this.unit,
      price: price ?? this.price,
      isDeal: isDeal ?? this.isDeal,
      originalPrice: originalPrice ?? this.originalPrice,
      store: store ?? this.store,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }
}
