import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:na2slna/models/grocery_item_model.dart';
import 'package:na2slna/models/household_model.dart';
import 'package:na2slna/providers/auth_provider.dart';
import 'package:na2slna/providers/grocery_list_provider.dart';
import 'package:na2slna/services/firestore_service.dart';

// All writes stay in memory. No Firebase project or device account is used.
class QaFixture {
  QaFixture._(this.db, this.service, this.container, this.household);
  final FakeFirebaseFirestore db;
  final FirestoreService service;
  final ProviderContainer container;
  final Household? household;
  static const uid = 'qa-owner';
  String get householdId => household!.id;
  String get listId => container.read(activeListIdProvider)!;

  static Future<QaFixture> create({
    bool withHousehold = true,
    bool gold = false,
    bool pro = true,
    FirestoreService Function(FakeFirebaseFirestore)? serviceFactory,
  }) async {
    final db = FakeFirebaseFirestore();
    final service = serviceFactory?.call(db) ?? FirestoreService(firestore: db);
    await service.createUserProfile(
      uid: uid,
      email: 'owner@example.test',
      displayName: 'QA Owner',
    );
    await db.collection('users').doc(uid).update({
      'isPro': pro,
      'isGold': gold,
      'fcmToken': 'local-test-token',
    });
    final household = withHousehold
        ? await service.createHousehold(name: 'QA Household', userId: uid)
        : null;
    final container = ProviderContainer(
      overrides: [
        firestoreServiceProvider.overrideWithValue(service),
        currentFirebaseUserProvider.overrideWithValue(
          MockUser(
            uid: uid,
            email: 'owner@example.test',
            displayName: 'QA Owner',
          ),
        ),
        appUserProvider.overrideWith((ref) => service.watchUser(uid)),
      ],
    );
    addTearDown(container.dispose);
    container.listen(appUserProvider, (_, _) {});
    container.listen(groceryListsProvider, (_, _) {});
    container.listen(groceryListProvider, (_, _) {});
    container.listen(smartSuggestionsProvider, (_, _) {});
    await container.read(appUserProvider.future);
    await container.read(groceryListsProvider.future);
    await container.read(groceryListProvider.future);
    return QaFixture._(db, service, container, household);
  }

  Future<void> add({
    String name = 'Milk',
    String quantity = '2',
    double price = 10,
    String category = 'Dairy & Eggs',
    String unit = 'pcs',
    String? imageUrl,
  }) async {
    await service.addGroceryItem(
      householdId: householdId,
      listId: listId,
      name: name,
      quantity: quantity,
      addedBy: uid,
      price: price,
      category: category,
      unit: unit,
      imageUrl: imageUrl,
    );
    await refresh();
  }

  Future<List<GroceryItem>> items() =>
      service.watchGroceryItems(householdId, listId).first;

  Future<void> refresh() async {
    container.invalidate(groceryListsProvider);
    await container.read(groceryListsProvider.future);
    container.invalidate(groceryListProvider);
    await container.read(groceryListProvider.future);
  }

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(430, 932),
    ThemeData? theme,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme ?? ThemeData(fontFamily: 'PlusJakartaSans'),
          home: child,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }
}
