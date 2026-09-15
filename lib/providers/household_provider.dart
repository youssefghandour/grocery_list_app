import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/household_model.dart';
import '../models/user_model.dart';
import '../providers/auth_provider.dart';

final householdProvider = StreamProvider<Household?>((ref) {
  final appUser = ref.watch(appUserProvider).value;
  if (appUser == null || !appUser.hasHousehold) {
    return Stream.value(null);
  }

  return ref
      .watch(firestoreServiceProvider)
      .watchHousehold(appUser.householdId!);
});

final householdMembersProvider = StreamProvider<List<AppUser>>((ref) {
  final appUser = ref.watch(appUserProvider).value;
  if (appUser == null || !appUser.hasHousehold) {
    return Stream.value([]);
  }

  return ref
      .watch(firestoreServiceProvider)
      .watchHouseholdMembers(appUser.householdId!);
});

class HouseholdController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> createHousehold(String name) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final uid = ref.read(currentFirebaseUserProvider)!.uid;
      await ref.read(firestoreServiceProvider).createHousehold(
            name: name,
            userId: uid,
          );
    });
  }

  Future<void> joinHousehold(String inviteCode) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final uid = ref.read(currentFirebaseUserProvider)!.uid;
      await ref.read(firestoreServiceProvider).joinHousehold(
            inviteCode: inviteCode,
            userId: uid,
          );
    });
  }

  Future<void> leaveHousehold() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final uid = ref.read(currentFirebaseUserProvider)!.uid;
      await ref.read(firestoreServiceProvider).leaveHousehold(uid);
    });
  }

  Future<void> removeMember(String targetUid) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(firestoreServiceProvider).leaveHousehold(targetUid);
    });
  }
}

final householdControllerProvider =
    NotifierProvider<HouseholdController, AsyncValue<void>>(HouseholdController.new);
