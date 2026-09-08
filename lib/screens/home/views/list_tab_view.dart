import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/grocery_item_model.dart';
import '../../../models/grocery_list_model.dart';
import '../../../models/household_model.dart';
import '../../../models/user_model.dart';
import '../../../providers/grocery_list_provider.dart';
import '../../../widgets/quick_add_bar.dart';
import '../../../widgets/empty_list_illustration.dart';
import '../../../widgets/error_screen.dart';
import '../widgets/home_top_header.dart';
import '../widgets/household_banner.dart';
import '../widgets/category_card.dart';

class ListTabView extends ConsumerWidget {
  const ListTabView({super.key, required this.appUser, required this.household});
  final AppUser appUser;
  final Household? household;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groceryAsync = ref.watch(groceryListProvider);
    final listsAsync = ref.watch(groceryListsProvider);
    final activeListId = ref.watch(activeListIdProvider);

    final activeListName = listsAsync.valueOrNull
            ?.firstWhere((l) => l.id == activeListId,
                orElse: () => GroceryList(
                    id: '',
                    name: 'My List',
                    createdBy: '',
                    isDefault: false,
                    createdAt: DateTime.now()))
            .name ??
        'My List';

    return SafeArea(
      child: Column(
        children: [
          HomeTopHeader(user: appUser),
          HouseholdBanner(household: household),
          Expanded(
            child: groceryAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => ErrorScreen(
                error: error.toString(),
                onRetry: () => ref.invalidate(groceryListProvider),
              ),
              data: (items) {
                final Map<String, List<GroceryItem>> grouped = {};
                for (var item in items) {
                  grouped.putIfAbsent(item.category, () => []).add(item);
                }

                return ListView(
                  children: [
                    const QuickAddBar(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            activeListName,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          TextButton.icon(
                            onPressed: () => _showListSettings(context, ref, listsAsync, activeListId),
                            icon: const Icon(Icons.more_horiz, size: 16),
                            label: const Text('Options', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                    ...grouped.entries.map((entry) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: CategoryCard(category: entry.key, items: entry.value),
                        )),
                    if (items.isEmpty) const EmptyListIllustration(),
                    const SizedBox(height: 100),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showListSettings(BuildContext context, WidgetRef ref, AsyncValue<List<GroceryList>> listsAsync, String? activeListId) {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Switch List', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ...listsAsync.maybeWhen(
            data: (lists) => lists.map((l) => ListTile(
                  title: Text(l.name),
                  selected: l.id == activeListId,
                  onTap: () {
                    ref.read(selectedListIdProvider.notifier).state = l.id;
                    Navigator.pop(context);
                  },
                )),
            orElse: () => [],
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Create New List'),
            onTap: () {
              Navigator.pop(context);
              _showCreateListDialog(context, ref);
            },
          ),
        ],
      ),
    );
  }

  void _showCreateListDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Shopping List'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'e.g. Weekly Groceries'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await ref.read(groceryListControllerProvider.notifier).addList(controller.text);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}
