import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'household_provider.dart';

// Family benefits come from the household's owner, never another member's role.
final householdGoldProvider = Provider<bool>((ref) {
  final user = ref.watch(appUserProvider).value;
  final household = ref.watch(householdProvider).value;
  final members = ref.watch(householdMembersProvider).value ?? [];
  if (user == null || household == null || user.householdId != household.id) {
    return false;
  }
  for (final member in members) {
    if (member.uid == household.createdBy &&
        member.householdId == household.id) {
      return member.isGold;
    }
  }
  return false;
});

final effectiveGoldProvider = Provider<bool>((ref) {
  final user = ref.watch(appUserProvider).value;
  return (user?.isGold ?? false) || ref.watch(householdGoldProvider);
});

final effectiveProProvider = Provider<bool>((ref) {
  final user = ref.watch(appUserProvider).value;
  return (user?.isPro ?? false) || ref.watch(effectiveGoldProvider);
});
