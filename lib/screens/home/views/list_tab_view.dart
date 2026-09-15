import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../models/grocery_item_model.dart';
import '../../../models/grocery_list_model.dart';
import '../../../models/household_model.dart';
import '../../../models/user_model.dart';
import '../../../providers/grocery_list_provider.dart';
import '../../../providers/entitlement_provider.dart';
import '../../../widgets/quick_add_bar.dart';
import '../../../widgets/empty_list_illustration.dart';
import '../../../widgets/error_screen.dart';
import '../widgets/home_top_header.dart';
import '../widgets/household_banner.dart';
import '../widgets/category_card.dart';
import '../../../widgets/banner_ad_widget.dart';

class ListTabView extends ConsumerWidget {
  const ListTabView({
    super.key,
    required this.appUser,
    required this.household,
  });
  final AppUser appUser;
  final Household? household;

  void _exportToWhatsApp(
    BuildContext context,
    List<GroceryItem> items,
    String listName,
  ) {
    if (items.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln('🛒 *Na2slna: $listName*');
    buffer.writeln('---------------------------');

    // Group items by category for a cleaner export
    final Map<String, List<GroceryItem>> grouped = {};
    for (var item in items) {
      grouped.putIfAbsent(item.category, () => []).add(item);
    }

    for (var entry in grouped.entries) {
      buffer.writeln('\n🔹 *${entry.key}*');
      for (var item in entry.value) {
        final checkMark = item.isChecked ? '✅' : '▫️';
        buffer.writeln(
          '$checkMark ${item.name} (${item.quantity} ${item.unit})',
        );
      }
    }

    buffer.writeln('\nGenerated via *Na2slna*');

    SharePlus.instance.share(ShareParams(text: buffer.toString()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groceryAsync = ref.watch(groceryListProvider);
    final listsAsync = ref.watch(groceryListsProvider);
    final activeListId = ref.watch(activeListIdProvider);
    final isGold = ref.watch(effectiveGoldProvider);
    final isPro = ref.watch(effectiveProProvider);

    final activeList = listsAsync.value?.firstWhere(
      (l) => l.id == activeListId,
      orElse: () => GroceryList(
        id: '',
        name: 'My List',
        createdBy: '',
        isDefault: false,
        createdAt: DateTime.now(),
      ),
    );

    final activeListName = activeList?.name ?? 'My List';

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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            activeListName,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          TextButton.icon(
                            onPressed: () => _showListSettings(
                              context,
                              ref,
                              listsAsync,
                              activeListId,
                              items,
                              isGold,
                              activeListName,
                            ),
                            icon: const Icon(Icons.more_horiz, size: 16),
                            label: const Text(
                              'Options',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ...grouped.entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: CategoryCard(
                          category: entry.key,
                          items: entry.value,
                        ),
                      ),
                    ),
                    if (items.isEmpty) const EmptyListIllustration(),
                    if (!isPro) const BannerAdWidget(),
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

  void _showListSettings(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<GroceryList>> listsAsync,
    String? activeListId,
    List<GroceryItem> items,
    bool isGold,
    String activeListName,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Options',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          if (isGold)
            ListTile(
              leading: const Icon(Icons.share, color: Colors.green),
              title: const Text('Export to WhatsApp'),
              onTap: () {
                Navigator.pop(context);
                _exportToWhatsApp(context, items, activeListName);
              },
            ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Switch List',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          ...listsAsync.maybeWhen(
            data: (lists) => lists.map(
              (l) => ListTile(
                title: Text(l.name),
                selected: l.id == activeListId,
                onTap: () {
                  ref.read(selectedListIdProvider.notifier).set(l.id);
                  Navigator.pop(context);
                },
              ),
            ),
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
    showDialog(context: context, builder: (ctx) => const _CreateListDialog());
  }
}

class _CreateListDialog extends ConsumerStatefulWidget {
  const _CreateListDialog();

  @override
  ConsumerState<_CreateListDialog> createState() => _CreateListDialogState();
}

class _CreateListDialogState extends ConsumerState<_CreateListDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(groceryListControllerProvider.notifier)
          .addList(_controller.text.trim());
      if (!mounted) return;
      if (ref.read(groceryListControllerProvider).hasError) {
        setState(() {
          _saving = false;
          _error = 'Could not create the list. Please try again.';
        });
        return;
      }
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not create the list. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Shopping List'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'e.g. Weekly Groceries',
              ),
              autofocus: true,
              enabled: !_saving,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a list name'
                  : null,
              onFieldSubmitted: (_) => _create(),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _create,
          child: Text(_saving ? 'Creating...' : 'Create'),
        ),
      ],
    );
  }
}
