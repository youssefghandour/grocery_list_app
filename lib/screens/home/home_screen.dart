import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/household_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/grocery_list_provider.dart';
import '../../providers/household_provider.dart';
import '../../widgets/add_item_dialog.dart';
import '../../widgets/grocery_item_tile.dart';
import '../../widgets/role_badge.dart';

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
      error: (error, _) => Scaffold(
        body: Center(child: Text('Error: $error')),
      ),
      data: (appUser) {
        if (appUser == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!appUser.hasHousehold) {
          return _OnboardingScreen(displayName: appUser.displayName);
        }

        return householdAsync.when(
          loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Scaffold(
            body: Center(child: Text('Error: $error')),
          ),
          data: (household) {
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
                  IconButton(
                    icon: const Icon(Icons.logout),
                    tooltip: 'Sign out',
                    onPressed: () =>
                        ref.read(authControllerProvider.notifier).signOut(),
                  ),
                ],
              ),
              body: groceryAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('Error: $error')),
                data: (items) {
                  if (items.isEmpty) {
                    return _EmptyList(onAdd: () => showAddItemDialog(context));
                  }

                  final unchecked =
                      items.where((i) => !i.isChecked).toList();
                  final checked = items.where((i) => i.isChecked).toList();

                  return RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(groceryListProvider);
                    },
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 88),
                      children: [
                        if (unchecked.isNotEmpty) ...[
                          _SectionHeader(title: 'To Buy (${unchecked.length})'),
                          ...unchecked.map(
                            (item) => GroceryItemTile(item: item),
                          ),
                        ],
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

  void _showHouseholdInfo(
    BuildContext context,
    WidgetRef ref,
    Household? household,
  ) {
    final membersAsync = ref.read(householdMembersProvider);

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
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
              membersAsync.when(
                loading: () => const CircularProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (members) => Column(
                  children: members
                      .map(
                        (m) => ListTile(
                          leading: CircleAvatar(
                            child: Text(m.displayName[0].toUpperCase()),
                          ),
                          title: Text(m.displayName),
                          subtitle: Text(m.email),
                          trailing: RoleBadge(role: m.role),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await ref
                      .read(householdControllerProvider.notifier)
                      .leaveHousehold();
                },
                child: const Text('Leave Household'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OnboardingScreen extends StatelessWidget {
  const _OnboardingScreen({required this.displayName});

  final String displayName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                Icons.home_outlined,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Welcome, $displayName!',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Create a new household or join an existing one to start sharing your grocery list.',
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
                label: const Text('Create Household'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.pushNamed(context, '/join-household'),
                icon: const Icon(Icons.group_add_outlined),
                label: const Text('Join with Invite Code'),
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

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
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
            'Add items and they will sync instantly\nacross all your devices.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add First Item'),
          ),
        ],
      ),
    );
  }
}
