import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:grocery_list_app/models/household_model.dart';
import 'package:grocery_list_app/models/user_model.dart';
import 'package:grocery_list_app/models/grocery_item_model.dart';
import 'package:grocery_list_app/models/grocery_list_model.dart';
import 'package:grocery_list_app/providers/auth_provider.dart';
import 'package:grocery_list_app/providers/grocery_list_provider.dart';
import 'package:grocery_list_app/providers/household_provider.dart';
import 'package:grocery_list_app/widgets/add_item_dialog.dart';
import 'package:grocery_list_app/widgets/grocery_item_tile.dart';
import 'package:grocery_list_app/widgets/quick_add_bar.dart';
import 'package:grocery_list_app/widgets/role_badge.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUserAsync = ref.watch(appUserProvider);
    final householdAsync = ref.watch(householdProvider);
    final groceryAsync = ref.watch(groceryListProvider);

    return appUserAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _ErrorScreen(
        error: error.toString(),
        onRetry: () => ref.invalidate(appUserProvider),
      ),
      data: (appUser) {
        if (appUser == null) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  const Text('Initializing your profile...'),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          ref.read(authControllerProvider.notifier).signOut(),
                      icon: const Icon(Icons.add_task),
                      label: const Text('Add to the lists'),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        if (!appUser.hasHousehold) {
          return _OnboardingScreen(displayName: appUser.displayName);
        }

        return householdAsync.when(
          loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => _ErrorScreen(
            error: error.toString(),
            onRetry: () => ref.invalidate(householdProvider),
          ),
          data: (household) {
            final listsAsync = ref.watch(groceryListsProvider);
            final activeListId = ref.watch(activeListIdProvider);

            return Scaffold(
              appBar: AppBar(
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(household?.name ?? 'Grocery List'),
                    Text(
                      'Synced in real time',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                          ),
                    ),
                  ],
                ),
                actions: [
                  RoleBadge(role: appUser.role),
                  IconButton(
                    icon: const Icon(Icons.group_outlined),
                    tooltip: 'Household info',
                    onPressed: () => _showHouseholdInfo(context, ref, household),
                  ),
                ],
              ),
              drawer: _buildDrawer(context, ref, listsAsync, activeListId),
              body: groceryAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (error, _) => _ErrorScreen(
                  error: error.toString(),
                  onRetry: () => ref.invalidate(groceryListProvider),
                ),
                data: (items) {
                  final unchecked =
                      items.where((i) => !i.isChecked).toList();
                  final checked = items.where((i) => i.isChecked).toList();

                  // Group by category
                  final Map<String, List<GroceryItem>> groupedItems = {};
                  for (final item in unchecked) {
                    groupedItems.putIfAbsent(item.category, () => []).add(item);
                  }
                  
                  // Calculate total budget
                  final totalBudget = items.fold<double>(0, (sum, item) => sum + (item.price));

                  return Column(
                    children: [
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: () async {
                            ref.invalidate(groceryListProvider);
                          },
                          child: ListView(
                            padding: const EdgeInsets.only(bottom: 88),
                            children: [
                              const QuickAddBar(),
                              if (items.isEmpty)
                                const _EmptyListIllustration(),
                              
                              // Display grouped unchecked items
                              ...groupedItems.entries.map((entry) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _SectionHeader(title: '${entry.key} (${entry.value.length})'),
                                    ...entry.value.map((item) => GroceryItemTile(item: item)),
                                  ],
                                );
                              }),

                              if (checked.isNotEmpty) ...[
                                _SectionHeader(
                                  title: 'In Cart (${checked.length})',
                                  trailing: TextButton(
                                    onPressed: () => ref
                                        .read(groceryListControllerProvider.notifier)
                                        .clearChecked(),
                                    child: const Text('Clear'),
                                  ),
                                ),
                                ...checked.map(
                                  (item) => GroceryItemTile(item: item),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (totalBudget > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          color: Theme.of(context).colorScheme.primaryContainer,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Total Estimated:',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              Text(
                                'EGP ${totalBudget.toStringAsFixed(2)}',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
              floatingActionButton: FloatingActionButton.extended(
                onPressed: () => showAddItemDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Add Item'),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDrawer(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<GroceryList>> listsAsync,
    String? activeListId,
  ) {
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
            child: Center(
              child: Text(
                'My Grocery Lists',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white),
              ),
            ),
          ),
          Expanded(
            child: listsAsync.when(
              data: (lists) => ListView(
                children: [
                  ...lists.map((list) => ListTile(
                        leading: const Icon(Icons.list),
                        title: Text(list.name),
                        selected: list.id == activeListId,
                        onTap: () {
                          ref.read(selectedListIdProvider.notifier).state = list.id;
                          Navigator.pop(context);
                        },
                      )),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Create New List'),
                    onTap: () {
                      Navigator.pop(context);
                      _showCreateListDialog(context, ref);
                    },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.local_offer_outlined),
                    title: const Text('Purchase Later / Deals'),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/purchase-later');
                    },
                  ),
                ],
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ListTile(title: Text('Error loading lists: $e')),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign Out'),
            onTap: () => ref.read(authControllerProvider.notifier).signOut(),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showCreateListDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Grocery List'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'e.g. Costco, Home Depot'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
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

  void _showHouseholdInfo(
    BuildContext context,
    WidgetRef ref,
    Household? household,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Consumer(
          builder: (context, ref, _) {
            final membersAsync = ref.watch(householdMembersProvider);
            final currentUser = ref.watch(appUserProvider).valueOrNull;

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    household?.name ?? 'Household',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Invite code: '),
                      SelectableText(
                        household?.inviteCode ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        onPressed: () {
                          Clipboard.setData(
                            ClipboardData(text: household?.inviteCode ?? ''),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Invite code copied')),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Members',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  membersAsync.maybeWhen(
                    data: (members) => Column(
                      children: members
                          .map((m) => _MemberTile(user: m, isMe: m.uid == currentUser?.uid))
                          .toList(),
                    ),
                    orElse: () => currentUser != null
                        ? _MemberTile(user: currentUser, isMe: true)
                        : const Center(child: LinearProgressIndicator()),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await ref.read(householdControllerProvider.notifier).leaveHousehold();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(color: Theme.of(context).colorScheme.error),
                    ),
                    child: const Text('Leave Household'),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.user, required this.isMe});

  final AppUser user;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: isMe ? Theme.of(context).colorScheme.primaryContainer : null,
        child: Text(user.displayName[0].toUpperCase()),
      ),
      title: Text(
        user.displayName + (isMe ? ' (You)' : ''),
        style: TextStyle(fontWeight: isMe ? FontWeight.bold : null),
      ),
      subtitle: Text(user.email),
      trailing: RoleBadge(role: user.role),
    );
  }
}

class _OnboardingScreen extends StatelessWidget {
  const _OnboardingScreen({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () =>
                ProviderScope.containerOf(context).read(authControllerProvider.notifier).signOut(),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                Icons.shopping_basket_outlined,
                size: 80,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Welcome, $displayName!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'You haven\'t joined a grocery list yet. Start your shared household list now!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () =>
                    Navigator.pushNamed(context, '/create-household'),
                icon: const Icon(Icons.add_home_outlined),
                label: const Text('Add to the lists'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.pushNamed(context, '/join-household'),
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Join an Existing List'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _EmptyListIllustration extends StatelessWidget {
  const _EmptyListIllustration();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_basket_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Your list is empty',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Add items using the bar above\nand they will sync instantly.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({
    required this.error,
    required this.onRetry,
  });

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isDatabaseMissing =
        error.contains('database (default) does not exist') ||
            error.contains('NOT_FOUND');
    final isOffline = error.contains('Unable to resolve host') ||
        error.contains('UnknownHostException') ||
        error.contains('UNAVAILABLE');

    String title = 'Something went wrong';
    String message = error;
    IconData icon = Icons.error_outline;

    if (isDatabaseMissing) {
      title = 'Firestore Not Initialized';
      message =
          'The Firestore database has not been created in your Firebase project. Please visit the Firebase Console to enable it.';
      icon = Icons.storage_outlined;
    } else if (isOffline) {
      title = 'No Internet Connection';
      message =
          'We can\'t reach the grocery servers. Please check your data or Wi-Fi connection and try again.';
      icon = Icons.cloud_off_outlined;
    }

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (isDatabaseMissing)
                const SelectionArea(
                  child: Text(
                    'https://console.firebase.google.com/',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ProviderScope.containerOf(context)
                    .read(authControllerProvider.notifier)
                    .signOut(),
                child: const Text('Back to Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
