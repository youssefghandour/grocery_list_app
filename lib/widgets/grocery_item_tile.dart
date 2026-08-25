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
    final match = ref.watch(itemMatchProvider(item.name));

    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Theme.of(context).colorScheme.error,
        child: Icon(
          Icons.delete_outline,
          color: Theme.of(context).colorScheme.onError,
        ),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete item?'),
            content: Text('Remove "${item.name}" from the list?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => controller.deleteItem(item.id),
      child: ListTile(
        leading: Checkbox(
          value: item.isChecked,
          onChanged: (_) => controller.toggleItem(item),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                item.name,
                style: TextStyle(
                  decoration: item.isChecked ? TextDecoration.lineThrough : null,
                  color: item.isChecked ? Theme.of(context).colorScheme.outline : null,
                ),
              ),
            ),
            if (match != null)
              Tooltip(
                message: 'Deal found at ${match.links.firstWhere((l) => l.isLowestPrice).storeName}! Lowest: EGP ${match.links.firstWhere((l) => l.isLowestPrice).price}',
                child: GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/purchase-later'),
                  child: Icon(
                    Icons.local_offer,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Row(
          children: [
            Text('Qty: ${item.quantity} ${item.unit}'),
            if (item.price > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'EGP ${item.price.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
            ],
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => showAddItemDialog(
            context,
            existingItem: item,
          ),
        ),
        onTap: () => controller.toggleItem(item),
      ),
    );
  }
}
