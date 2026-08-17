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
        title: Text(
          item.name,
          style: TextStyle(
            decoration: item.isChecked ? TextDecoration.lineThrough : null,
            color: item.isChecked
                ? Theme.of(context).colorScheme.outline
                : null,
          ),
        ),
        subtitle: Text('Qty: ${item.quantity}'),
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
