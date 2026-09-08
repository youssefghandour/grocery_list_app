import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/grocery_item_model.dart';
import '../providers/grocery_list_provider.dart';
import 'add_item_dialog.dart';

class GroceryItemTile extends ConsumerWidget {
  const GroceryItemTile({super.key, required this.item});

  final GroceryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(groceryListControllerProvider.notifier);
    final theme = Theme.of(context);

    final isDark = theme.brightness == Brightness.dark;

    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => controller.deleteItem(item.id),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: theme.colorScheme.error,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Item?'),
            content: Text('Remove "${item.name}" from your list?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Delete', style: TextStyle(color: theme.colorScheme.error)),
              ),
            ],
          ),
        );
      },
      child: Opacity(
        opacity: item.isChecked ? 0.6 : 1.0,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? theme.colorScheme.surfaceContainer : const Color(0xFFF1F5EB),
            borderRadius: BorderRadius.circular(16),
            border: item.isDeal
                ? Border.all(color: theme.colorScheme.secondary.withValues(alpha: 0.5), width: 1.5)
                : null,
          ),
          child: Row(
            children: [
              Checkbox(
                value: item.isChecked,
                onChanged: (_) => controller.toggleItem(item),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                visualDensity: VisualDensity.compact,
                activeColor: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: InkWell(
                  onTap: () => showAddItemDialog(context, existingItem: item),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          decoration: item.isChecked ? TextDecoration.lineThrough : null,
                          fontSize: 15,
                          color: isDark ? theme.colorScheme.onSurface : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item.quantity} ${item.unit}${item.price > 0 ? ' • ${item.price.toStringAsFixed(2)} EGP/${item.unit}' : ''}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (item.price > 0)
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        (item.price * (double.tryParse(item.quantity) ?? 1.0)).toStringAsFixed(2),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isDark ? theme.colorScheme.primary : null,
                        ),
                      ),
                      Text(
                        'EGP',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 9,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                decoration: BoxDecoration(
                  color: isDark 
                    ? theme.colorScheme.surfaceContainerHigh 
                    : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        (double.tryParse(item.quantity) ?? 1.0) > 1 ? Icons.remove : Icons.delete_outline,
                        size: 14,
                      ),
                      onPressed: () async {
                        final q = double.tryParse(item.quantity) ?? 1.0;
                        if (q > 1) {
                          controller.updateItem(item.copyWith(quantity: (q - 1).toString()));
                        } else {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete Item?'),
                              content: Text('Remove "${item.name}" from your list?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text('Delete', style: TextStyle(color: theme.colorScheme.error)),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            controller.deleteItem(item.id);
                          }
                        }
                      },
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                      color: (double.tryParse(item.quantity) ?? 1.0) > 1 
                        ? (isDark ? theme.colorScheme.onSurface : null)
                        : theme.colorScheme.error,
                    ),
                    Text(
                      item.quantity,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? theme.colorScheme.onSurface : null,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 14),
                      onPressed: () {
                        final q = double.tryParse(item.quantity) ?? 1.0;
                        controller.updateItem(item.copyWith(quantity: (q + 1).toString()));
                      },
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                      color: isDark ? theme.colorScheme.onSurface : null,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
