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

  factory GroceryItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return GroceryItem(
      id: doc.id,
      name: data['name'] as String? ?? '',
      quantity: data['quantity'] as String? ?? '1',
      isChecked: data['isChecked'] as bool? ?? false,
      addedBy: data['addedBy'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      category: data['category'] as String? ?? 'Other',
      unit: data['unit'] as String? ?? 'pcs',
      price: (data['price'] as num?)?.toDouble() ?? 0.0,
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
    );
  }
}
