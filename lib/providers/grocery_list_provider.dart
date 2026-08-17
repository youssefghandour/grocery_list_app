import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/grocery_item_model.dart';
import '../providers/auth_provider.dart';
import '../providers/household_provider.dart';

/// Real-time grocery list stream — Firestore snapshots push updates instantly
/// to every connected iOS, Android, and Web client.
final groceryListProvider = StreamProvider<List<GroceryItem>>((ref) {
  final appUser = ref.watch(appUserProvider).valueOrNull;
  if (appUser == null || !appUser.hasHousehold) {
    return Stream.value([]);
  }

  return ref
      .watch(firestoreServiceProvider)
      .watchGroceryItems(appUser.householdId!);
});

class GroceryListController extends StateNotifier<AsyncValue<void>> {
  GroceryListController(this._ref) : super(const AsyncData(null));

  final Ref _ref;

  String? get _householdId =>
      _ref.read(appUserProvider).valueOrNull?.householdId;

  String? get _userId => _ref.read(currentFirebaseUserProvider)?.uid;

  Future<void> addItem({
    required String name,
    required String quantity,
  }) async {
    final householdId = _householdId;
    final userId = _userId;
    if (householdId == null || userId == null) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _ref.read(firestoreServiceProvider).addGroceryItem(
            householdId: householdId,
            name: name,
            quantity: quantity,
            addedBy: userId,
          );
    });
  }

  Future<void> updateItem(GroceryItem item) async {
    final householdId = _householdId;
    if (householdId == null) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _ref.read(firestoreServiceProvider).updateGroceryItem(
            householdId: householdId,
            item: item,
          );
    });
  }

  Future<void> toggleItem(GroceryItem item) async {
    final householdId = _householdId;
    if (householdId == null) return;

    await _ref.read(firestoreServiceProvider).toggleGroceryItem(
          householdId: householdId,
          item: item,
        );
  }

  Future<void> deleteItem(String itemId) async {
    final householdId = _householdId;
    if (householdId == null) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _ref.read(firestoreServiceProvider).deleteGroceryItem(
            householdId: householdId,
            itemId: itemId,
          );
    });
  }

  Future<void> clearChecked() async {
    final householdId = _householdId;
    if (householdId == null) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _ref
          .read(firestoreServiceProvider)
          .clearCheckedItems(householdId);
    });
  }
}

final groceryListControllerProvider =
    StateNotifierProvider<GroceryListController, AsyncValue<void>>((ref) {
  return GroceryListController(ref);
});

/// Derived providers for UI convenience.
final uncheckedItemsProvider = Provider<List<GroceryItem>>((ref) {
  return ref
      .watch(groceryListProvider)
      .maybeWhen(
        data: (items) => items.where((i) => !i.isChecked).toList(),
        orElse: () => [],
      );
});

final checkedItemsProvider = Provider<List<GroceryItem>>((ref) {
  return ref
      .watch(groceryListProvider)
      .maybeWhen(
        data: (items) => items.where((i) => i.isChecked).toList(),
        orElse: () => [],
      );
});
