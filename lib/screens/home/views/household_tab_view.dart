import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/household_model.dart';
import '../../../models/user_model.dart';
import '../../../providers/household_provider.dart';
import '../../../providers/entitlement_provider.dart';
import '../widgets/home_top_header.dart';
import '../widgets/household_widgets.dart';

class HouseholdTabView extends ConsumerWidget {
  const HouseholdTabView({
    super.key,
    required this.appUser,
    required this.household,
  });
  final AppUser appUser;
  final Household? household;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(householdMembersProvider);
    final householdGold = ref.watch(householdGoldProvider);
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        children: [
          HomeTopHeader(user: appUser),
          const SizedBox(height: 16),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Text(
                  'Household Settings',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Manage members, invites, and household preferences.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                FamilyOverviewCard(
                  household: household,
                  memberCount: membersAsync.value?.length ?? 0,
                ),
                const SizedBox(height: 20),
                InviteCodeCard(household: household),
                const SizedBox(height: 24),
                MembersHeader(
                  count: membersAsync.value?.length ?? 0,
                  isUnlimited: householdGold,
                ),
                const SizedBox(height: 12),
                membersAsync.when(
                  data: (members) => Column(
                    children: [
                      ...members.map(
                        (m) => MemberTile(user: m, isMe: m.uid == appUser.uid),
                      ),
                    ],
                  ),
                  loading: () => const Center(child: LinearProgressIndicator()),
                  error: (e, _) => Text('Error loading members: $e'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
