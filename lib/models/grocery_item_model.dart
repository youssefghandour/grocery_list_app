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
  });

  final String id;
  final String name;
  final String quantity;
  final bool isChecked;
  final String addedBy;
  final DateTime createdAt;
  final DateTime updatedAt;

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
    };
  }

  GroceryItem copyWith({
    String? name,
    String? quantity,
    bool? isChecked,
    DateTime? updatedAt,
  }) {
    return GroceryItem(
      id: id,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      isChecked: isChecked ?? this.isChecked,
      addedBy: addedBy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
