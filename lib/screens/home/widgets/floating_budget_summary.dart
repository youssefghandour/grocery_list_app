import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/grocery_list_provider.dart';
import '../../../widgets/add_item_dialog.dart';

class FloatingBudgetSummary extends ConsumerWidget {
  const FloatingBudgetSummary({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final items = ref.watch(groceryListProvider).value ?? [];

    final total = items.fold<double>(0, (sum, item) {
      final q = double.tryParse(item.quantity) ?? 1.0;
      return sum + (item.price * q);
    });

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Card(
              elevation: isDark ? 8 : 4,
              margin: EdgeInsets.zero,
              color: isDark ? theme.colorScheme.surfaceContainer : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.shopping_cart_outlined, size: 14, color: theme.colorScheme.primary),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '${items.length} items in list',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: isDark ? theme.colorScheme.onSurface : null,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Estimated Total',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w300,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: total.toStringAsFixed(2),
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextSpan(
                            text: ' EGP',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            onPressed: () => showAddItemDialog(context),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: isDark ? theme.colorScheme.primaryContainer : const Color(0xFF0D631B),
            child: const Icon(Icons.add, color: Colors.white, size: 32),
          ),
        ],
      ),
    );
  }
}
