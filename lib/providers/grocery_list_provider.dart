import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/grocery_item_model.dart';
import '../models/grocery_list_model.dart';
import '../providers/auth_provider.dart';

/// Watch all grocery lists in the household.
final groceryListsProvider = StreamProvider<List<GroceryList>>((ref) {
  final appUser = ref.watch(appUserProvider).value;
  if (appUser == null || !appUser.hasHousehold) {
    return Stream.value([]);
  }

  return ref
      .watch(firestoreServiceProvider)
      .watchGroceryLists(appUser.householdId!);
});

/// Tracks the manually selected list ID.
final selectedListIdProvider =
    NotifierProvider<SelectedListIdNotifier, String?>(
      SelectedListIdNotifier.new,
    );

class SelectedListIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? id) => state = id;
}

/// Resolves the effective active list ID (selected or default).
final activeListIdProvider = Provider<String?>((ref) {
  final selectedId = ref.watch(selectedListIdProvider);
  final listsState = ref.watch(groceryListsProvider);
  // Do not reuse the previous household's lists while its replacement loads.
  if (listsState.isLoading) return null;
  final lists = listsState.value;
  if (lists == null || lists.isEmpty) return null;
  if (lists.any((list) => list.id == selectedId)) return selectedId;

  final defaultList = lists.firstWhere(
    (l) => l.isDefault,
    orElse: () => lists.first,
  );
  return defaultList.id;
});

/// Real-time grocery items for the ACTIVE list.
final groceryListProvider = StreamProvider<List<GroceryItem>>((ref) {
  final appUser = ref.watch(appUserProvider).value;
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
  final appUser = ref.watch(appUserProvider).value;
  if (appUser == null || !appUser.hasHousehold) {
    return Stream.value([]);
  }

  return ref
      .watch(firestoreServiceProvider)
      .watchSmartSuggestions(appUser.householdId!);
});

/*
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
*/

class GroceryListController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  String? get _householdId => ref.read(appUserProvider).value?.householdId;

  String? get _userId => ref.read(currentFirebaseUserProvider)?.uid;

  String? get _activeListId => ref.read(activeListIdProvider);

  Future<void> addList(String name) async {
    final householdId = _householdId;
    final userId = _userId;
    if (householdId == null || userId == null) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref
          .read(firestoreServiceProvider)
          .addGroceryList(householdId: householdId, name: name, userId: userId);
    });
  }

  Future<void> addItem({
    required String name,
    required String quantity,
    String category = 'Other',
    String unit = 'pcs',
    double price = 0.0,
    String? imageUrl,
  }) async {
    final householdId = _householdId;
    final userId = _userId;
    if (householdId == null || userId == null) {
      state = AsyncError(
        StateError('Join a household before adding items.'),
        StackTrace.current,
      );
      return;
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (!price.isFinite || price < 0) {
        throw ArgumentError.value(
          price,
          'price',
          'Must be a finite, non-negative number',
        );
      }
      await ref.read(groceryListsProvider.future);
      String? listId = _activeListId;

      // If no list exists (e.g. for existing households), create a default one first
      if (listId == null) {
        await ref
            .read(firestoreServiceProvider)
            .addGroceryList(
              householdId: householdId,
              name: 'Main List',
              userId: userId,
            );
        ref.invalidate(groceryListsProvider);
        final lists = await ref.read(groceryListsProvider.future);
        if (lists.isNotEmpty) {
          listId = lists.first.id;
          ref.read(selectedListIdProvider.notifier).set(listId);
        }
      }

      if (listId != null) {
        // Check if item already exists in the CURRENT list
        final currentItems = await ref.read(groceryListProvider.future);
        final existingItem = currentItems.firstWhere(
          (item) => item.name.trim().toLowerCase() == name.trim().toLowerCase(),
          orElse: () => GroceryItem(
            id: '',
            name: '',
            quantity: '',
            isChecked: false,
            addedBy: '',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );

        if (existingItem.id.isNotEmpty) {
          final currentQty = num.tryParse(existingItem.quantity);
          final addQty = num.tryParse(quantity);
          // Preserve descriptive quantities rather than silently replacing them.
          final canAdd =
              currentQty != null &&
              currentQty.isFinite &&
              addQty != null &&
              addQty.isFinite;

          await ref
              .read(firestoreServiceProvider)
              .updateGroceryItem(
                householdId: householdId,
                listId: listId,
                item: existingItem.copyWith(
                  quantity: canAdd
                      ? (currentQty + addQty).toString()
                      : existingItem.quantity,
                  price: price > 0 ? price : existingItem.price,
                  category: category != 'Other'
                      ? category
                      : existingItem.category,
                  imageUrl: imageUrl ?? existingItem.imageUrl,
                  updatedAt: DateTime.now(),
                ),
              );
        } else {
          await ref
              .read(firestoreServiceProvider)
              .addGroceryItem(
                householdId: householdId,
                listId: listId,
                name: name,
                quantity: quantity,
                addedBy: userId,
                category: category,
                unit: unit,
                price: price,
                imageUrl: imageUrl,
              );
        }
      }
    });
  }

  Future<void> updateItem(GroceryItem item) async {
    final householdId = _householdId;
    final listId = _activeListId;
    if (householdId == null || listId == null) {
      state = AsyncError(
        StateError('Select a household list before saving.'),
        StackTrace.current,
      );
      return;
    }

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (!item.price.isFinite || item.price < 0) {
        throw ArgumentError.value(
          item.price,
          'price',
          'Must be a finite, non-negative number',
        );
      }
      await ref
          .read(firestoreServiceProvider)
          .updateGroceryItem(
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

    await ref
        .read(firestoreServiceProvider)
        .toggleGroceryItem(
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
      await ref
          .read(firestoreServiceProvider)
          .deleteGroceryItem(
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
      await ref
          .read(firestoreServiceProvider)
          .clearCheckedItems(householdId, listId);
    });
  }
}

final groceryListControllerProvider =
    NotifierProvider<GroceryListController, AsyncValue<void>>(
      GroceryListController.new,
    );

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
