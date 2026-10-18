import 'package:cloud_firestore/cloud_firestore.dart';

class RecurringListTemplate {
  const RecurringListTemplate({
    required this.id,
    required this.name,
    required this.items,
    required this.createdBy,
    required this.createdAt,
  });

  final String id;
  final String name;
  final List<RecurringListTemplateItem> items;
  final String createdBy;
  final DateTime createdAt;

  factory RecurringListTemplate.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    final rawItems = data['items'] as List<dynamic>? ?? const [];
    return RecurringListTemplate(
      id: doc.id,
      name: data['name'] as String? ?? 'Saved list',
      items: rawItems
          .whereType<Map>()
          .map(
            (item) => RecurringListTemplateItem.fromMap(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(),
      createdBy: data['createdBy'] as String? ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'items': items.map((item) => item.toMap()).toList(),
    'createdBy': createdBy,
    'createdAt': Timestamp.fromDate(createdAt),
  };
}

class RecurringListTemplateItem {
  const RecurringListTemplateItem({
    required this.name,
    required this.quantity,
    required this.category,
    required this.unit,
    required this.price,
    this.imageUrl,
  });

  final String name;
  final String quantity;
  final String category;
  final String unit;
  final double price;
  final String? imageUrl;

  factory RecurringListTemplateItem.fromMap(Map<String, dynamic> data) {
    final rawPrice = data['price'];
    return RecurringListTemplateItem(
      name: data['name'] is String ? data['name'] as String : '',
      quantity: data['quantity'] is String ? data['quantity'] as String : '1',
      category: data['category'] is String
          ? data['category'] as String
          : 'Other',
      unit: data['unit'] is String ? data['unit'] as String : 'pcs',
      price: rawPrice is num && rawPrice.isFinite ? rawPrice.toDouble() : 0,
      imageUrl: data['imageUrl'] is String ? data['imageUrl'] as String : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'quantity': quantity,
    'category': category,
    'unit': unit,
    'price': price,
    if (imageUrl != null) 'imageUrl': imageUrl,
  };
}
