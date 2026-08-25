import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/grocery_item_model.dart';
import '../models/grocery_list_model.dart';
import '../models/product_cache_model.dart';
import '../providers/auth_provider.dart';
import '../services/background_search_service.dart';

/// Watch all grocery lists in the household.
final groceryListsProvider = StreamProvider<List<GroceryList>>((ref) {
  final appUser = ref.watch(appUserProvider).valueOrNull;
  if (appUser == null || !appUser.hasHousehold) {
    return Stream.value([]);
  }

  return ref
      .watch(firestoreServiceProvider)
      .watchGroceryLists(appUser.householdId!);
});

/// Tracks the manually selected list ID.
final selectedListIdProvider = StateProvider<String?>((ref) => null);

/// Resolves the effective active list ID (selected or default).
final activeListIdProvider = Provider<String?>((ref) {
  final selectedId = ref.watch(selectedListIdProvider);
  if (selectedId != null) return selectedId;

  final lists = ref.watch(groceryListsProvider).valueOrNull;
  if (lists == null || lists.isEmpty) return null;

  final defaultList =
      lists.firstWhere((l) => l.isDefault, orElse: () => lists.first);
  return defaultList.id;
});

/// Real-time grocery items for the ACTIVE list.
final groceryListProvider = StreamProvider<List<GroceryItem>>((ref) {
  final appUser = ref.watch(appUserProvider).valueOrNull;
  final listId = ref.watch(activeListIdProvider);
  
  if (appUser == null || !appUser.hasHousehold || listId == null) {
    return Stream.value([]);
  }

  return ref
      .watch(firestoreServiceProvider)
      .watchGroceryItems(appUser.householdId!, listId);
});

/// Smart suggestions based on previous items.
final smartSuggestionsProvider = StreamProvider<List<String>>((ref) {
  final appUser = ref.watch(appUserProvider).valueOrNull;
  if (appUser == null || !appUser.hasHousehold) {
    return Stream.value([]);
  }

  return ref
      .watch(firestoreServiceProvider)
      .watchSmartSuggestions(appUser.householdId!);
});

/// Watches cached products for the household's shopping history.
final purchaseLaterProvider = StreamProvider<List<ProductMatch>>((ref) {
  final firestore = FirebaseFirestore.instance;
  return firestore.collection('product_cache').snapshots().map((snapshot) {
    return snapshot.docs.map((doc) => ProductMatch.fromFirestore(doc)).toList();
  });
});

/// Checks if a specific item has a cached product match.
final itemMatchProvider = Provider.family<ProductMatch?, String>((ref, itemName) {
  final matches = ref.watch(purchaseLaterProvider).valueOrNull ?? [];
  final term = itemName.trim().toLowerCase();
  try {
    return matches.firstWhere((m) => m.searchTerm == term);
  } catch (_) {
    return null;
  }
});

class GroceryListController extends StateNotifier<AsyncValue<void>> {
  GroceryListController(this._ref) : super(const AsyncData(null));

  final Ref _ref;

  String? get _householdId =>
      _ref.read(appUserProvider).valueOrNull?.householdId;

  String? get _userId => _ref.read(currentFirebaseUserProvider)?.uid;

  String? get _activeListId => _ref.read(activeListIdProvider);

  Future<void> addList(String name) async {
    final householdId = _householdId;
    final userId = _userId;
    if (householdId == null || userId == null) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _ref.read(firestoreServiceProvider).addGroceryList(
            householdId: householdId,
            name: name,
            userId: userId,
          );
    });
  }

  Future<void> addItem({
    required String name,
    required String quantity,
    String category = 'Other',
    String unit = 'pcs',
    double price = 0.0,
  }) async {
    final householdId = _householdId;
    final userId = _userId;
    if (householdId == null || userId == null) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      String? listId = _activeListId;

      // If no list exists (e.g. for existing households), create a default one first
      if (listId == null) {
        await _ref.read(firestoreServiceProvider).addGroceryList(
              householdId: householdId,
              name: 'Main List',
              userId: userId,
            );
        // The StreamProvider will update and pick up the new list.
        // We need to wait a moment or find the ID.
        final lists = await _ref.read(groceryListsProvider.future);
        if (lists.isNotEmpty) {
          listId = lists.first.id;
          _ref.read(selectedListIdProvider.notifier).state = listId;
        }
      }

      if (listId != null) {
        await _ref.read(firestoreServiceProvider).addGroceryItem(
              householdId: householdId,
              listId: listId,
              name: name,
              quantity: quantity,
              addedBy: userId,
              category: category,
              unit: unit,
              price: price,
            );
        
        // Trigger secret background search
        _ref.read(backgroundSearchServiceProvider).searchAndCache(name);
      }
    });
  }

  Future<void> updateItem(GroceryItem item) async {
    final householdId = _householdId;
    final listId = _activeListId;
    if (householdId == null || listId == null) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _ref.read(firestoreServiceProvider).updateGroceryItem(
            householdId: householdId,
            listId: listId,
            item: item,
          );
    });
  }

  Future<void> toggleItem(GroceryItem item) async {
    final householdId = _householdId;
    final listId = _activeListId;
    if (householdId == null || listId == null) return;

    await _ref.read(firestoreServiceProvider).toggleGroceryItem(
          householdId: householdId,
          listId: listId,
          item: item,
        );
  }

  Future<void> deleteItem(String itemId) async {
    final householdId = _householdId;
    final listId = _activeListId;
    if (householdId == null || listId == null) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _ref.read(firestoreServiceProvider).deleteGroceryItem(
            householdId: householdId,
            listId: listId,
            itemId: itemId,
          );
    });
  }

  Future<void> clearChecked() async {
    final householdId = _householdId;
    final listId = _activeListId;
    if (householdId == null || listId == null) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _ref
          .read(firestoreServiceProvider)
          .clearCheckedItems(householdId, listId);
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
