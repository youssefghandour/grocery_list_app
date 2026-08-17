import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/household_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';

final householdProvider = StreamProvider<Household?>((ref) {
  final appUser = ref.watch(appUserProvider).valueOrNull;
  if (appUser == null || !appUser.hasHousehold) {
    return Stream.value(null);
  }

  return ref
      .watch(firestoreServiceProvider)
      .watchHousehold(appUser.householdId!);
});

final householdMembersProvider = StreamProvider<List<AppUser>>((ref) {
  final appUser = ref.watch(appUserProvider).valueOrNull;
  if (appUser == null || !appUser.hasHousehold) {
    return Stream.value([]);
  }

  return ref
      .watch(firestoreServiceProvider)
      .watchHouseholdMembers(appUser.householdId!);
});

class HouseholdController extends StateNotifier<AsyncValue<void>> {
  HouseholdController(this._ref) : super(const AsyncData(null));

  final Ref _ref;

  Future<void> createHousehold(String name) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final uid = _ref.read(currentFirebaseUserProvider)!.uid;
      await _ref.read(firestoreServiceProvider).createHousehold(
            name: name,
            userId: uid,
          );
    });
  }

  Future<void> joinHousehold(String inviteCode) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final uid = _ref.read(currentFirebaseUserProvider)!.uid;
      await _ref.read(firestoreServiceProvider).joinHousehold(
            inviteCode: inviteCode,
            userId: uid,
          );
    });
  }

  Future<void> leaveHousehold() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final uid = _ref.read(currentFirebaseUserProvider)!.uid;
      await _ref.read(firestoreServiceProvider).leaveHousehold(uid);
    });
  }
}

final householdControllerProvider =
    StateNotifierProvider<HouseholdController, AsyncValue<void>>((ref) {
  return HouseholdController(ref);
});
