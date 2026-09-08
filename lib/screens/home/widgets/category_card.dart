import 'package:flutter/material.dart';
import '../../../models/grocery_item_model.dart';
import '../../../widgets/grocery_item_tile.dart';

class CategoryCard extends StatelessWidget {
  const CategoryCard({super.key, required this.category, required this.items});
  final String category;
  final List<GroceryItem> items;

  IconData _getIcon() {
    switch (category.toLowerCase()) {
      case 'produce': return Icons.apple;
      case 'dairy & eggs': return Icons.water_drop_outlined;
      case 'bakery': return Icons.bakery_dining_outlined;
      case 'meat & seafood': return Icons.kebab_dining_outlined;
      case 'frozen foods': return Icons.ac_unit;
      default: return Icons.category_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surfaceContainerLow : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isDark
              ? theme.colorScheme.outlineVariant.withValues(alpha: 0.2)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Icon(_getIcon(), size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    category,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      color: isDark ? theme.colorScheme.onSurface : null,
                    ),
                  ),
                ),
                Text(
                  '${items.length} items',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Column(
              children: items.map((item) => GroceryItemTile(item: item)).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
