import 'package:cloud_firestore/cloud_firestore.dart';

class GroceryList {
  const GroceryList({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.createdAt,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final String createdBy;
  final DateTime createdAt;
  final bool isDefault;

  factory GroceryList.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return GroceryList(
      id: doc.id,
      name: data['name'] as String? ?? 'Unnamed List',
      createdBy: data['createdBy'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isDefault: data['isDefault'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'isDefault': isDefault,
    };
  }

  GroceryList copyWith({
    String? name,
    bool? isDefault,
  }) {
    return GroceryList(
      id: id,
      name: name ?? this.name,
      createdBy: createdBy,
      createdAt: createdAt,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}
