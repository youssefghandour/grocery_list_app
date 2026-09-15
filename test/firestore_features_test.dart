import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:na2slna/services/firestore_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:na2slna/constants/user_roles.dart';
import 'support/qa_fixture.dart';

void main() {
  test(
    'Household creation creates admin, invitation and default list records',
    () async {
      final f = await QaFixture.create();
      final owner = await f.service.getUser(QaFixture.uid);
      expect(owner!.householdId, f.householdId);
      expect(owner.role, UserRole.familyAdmin);
      expect(f.household!.inviteCode, matches(RegExp(r'^[A-HJ-NP-Z2-9]{6}$')));
      expect(
        (await f.db.doc('inviteCodes/${f.household!.inviteCode}').get())
            .data()!['householdId'],
        f.householdId,
      );
      final lists = await f.service.watchGroceryLists(f.householdId).first;
      expect(lists.single.name, 'Main List');
      expect(lists.single.isDefault, isTrue);
    },
  );

  // Server membership/expiry/cap behavior is tested against the real callable in
  // qa/household-tests.cjs. These tests cover the client transport contract.
  test(
    'Join normalizes the code and returns the server-selected household',
    () async {
      String? received;
      final f = await QaFixture.create();
      final service = FirestoreService(
        firestore: f.db,
        acceptInvitation: (code) async {
          received = code;
          return f.householdId;
        },
      );
      final result = await service.joinHousehold(
        inviteCode: '  abc234 ',
        userId: QaFixture.uid,
      );
      expect(received, 'ABC234');
      expect(result.id, f.householdId);
    },
  );

  test('Malformed invitation is rejected before calling the server', () async {
    final f = await QaFixture.create();
    var called = false;
    final service = FirestoreService(
      firestore: f.db,
      acceptInvitation: (_) async {
        called = true;
        return f.householdId;
      },
    );
    await expectLater(
      service.joinHousehold(inviteCode: '../x', userId: QaFixture.uid),
      throwsA(isA<FirebaseException>()),
    );
    expect(called, false);
  });

  for (final reason in [
    'invite-not-found',
    'invite-expired',
    'limit-reached',
  ]) {
    test(
      'Server $reason leaves local membership unchanged and reaches the caller',
      () async {
        final f = await QaFixture.create();
        final service = FirestoreService(
          firestore: f.db,
          acceptInvitation: (_) async {
            throw FirebaseFunctionsException(
              code: 'failed-precondition',
              message: 'Cannot join.',
              details: {'reason': reason},
            );
          },
        );
        await expectLater(
          service.joinHousehold(inviteCode: 'ABC234', userId: QaFixture.uid),
          throwsA(
            isA<FirebaseException>().having((e) => e.code, 'code', reason),
          ),
        );
        expect(
          (await f.service.getUser(QaFixture.uid))!.householdId,
          f.householdId,
        );
      },
    );
  }

  test('Missing household after server acceptance reports an error', () async {
    final f = await QaFixture.create();
    final service = FirestoreService(
      firestore: f.db,
      acceptInvitation: (_) async => 'deleted',
    );
    await expectLater(
      service.joinHousehold(inviteCode: 'ABC234', userId: QaFixture.uid),
      throwsA(
        isA<FirebaseException>().having(
          (e) => e.code,
          'code',
          'household-not-found',
        ),
      ),
    );
  });

  test('Leave removes membership and preserves profile', () async {
    final f = await QaFixture.create();
    await f.service.leaveHousehold(QaFixture.uid);
    final owner = await f.service.getUser(QaFixture.uid);
    expect(owner!.hasHousehold, isFalse);
    expect(owner.role, UserRole.familyMember);
    expect(owner.displayName, 'QA Owner');
  });

  test('Profile name, notification setting and device token persist', () async {
    final f = await QaFixture.create();
    await f.service.updateDisplayName(QaFixture.uid, 'Updated Name');
    await f.service.updateNotificationPreference(QaFixture.uid, false);
    await f.service.updateFcmToken(QaFixture.uid, 'replacement-token');
    final user = await f.service.getUser(QaFixture.uid);
    expect(user!.displayName, 'Updated Name');
    expect(user.notificationsEnabled, false);
    expect(user.fcmToken, 'replacement-token');
  });

  test('Rename household trims whitespace', () async {
    final f = await QaFixture.create();
    await f.service.updateHouseholdName(f.householdId, '  New Family  ');
    expect(
      (await f.service.watchHousehold(f.householdId).first)!.name,
      'New Family',
    );
  });

  test('Add and edit item preserve fields and per-unit pricing', () async {
    final f = await QaFixture.create();
    await f.add(name: ' Milk ', quantity: ' 2 ', price: 25.5, unit: 'L');
    final item = (await f.items()).single;
    expect(item.name, 'Milk');
    expect(item.quantity, '2');
    expect(item.price, 25.5);
    expect(item.unit, 'L');
    await f.service.updateGroceryItem(
      householdId: f.householdId,
      listId: f.listId,
      item: item.copyWith(
        name: 'Fresh Milk',
        quantity: '3',
        price: 30,
        category: 'Beverages',
      ),
    );
    final updated = (await f.items()).single;
    expect(updated.name, 'Fresh Milk');
    expect(updated.quantity, '3');
    expect(updated.price * double.parse(updated.quantity), 90);
    expect(updated.category, 'Beverages');
  });

  test('Check and uncheck preserve item identity', () async {
    final f = await QaFixture.create();
    await f.add();
    var item = (await f.items()).single;
    await f.service.toggleGroceryItem(
      householdId: f.householdId,
      listId: f.listId,
      item: item,
    );
    item = (await f.items()).single;
    expect(item.isChecked, true);
    await f.service.toggleGroceryItem(
      householdId: f.householdId,
      listId: f.listId,
      item: item,
    );
    expect((await f.items()).single.isChecked, false);
  });

  test('Delete only removes the requested item', () async {
    final f = await QaFixture.create();
    await f.add(name: 'Milk');
    await f.add(name: 'Bread');
    final milk = (await f.items()).firstWhere((i) => i.name == 'Milk');
    await f.service.deleteGroceryItem(
      householdId: f.householdId,
      listId: f.listId,
      itemId: milk.id,
    );
    expect((await f.items()).single.name, 'Bread');
  });

  test(
    'Clear purchased removes checked items and retains unchecked items',
    () async {
      final f = await QaFixture.create();
      await f.add(name: 'Milk');
      await f.add(name: 'Bread');
      await f.service.toggleGroceryItem(
        householdId: f.householdId,
        listId: f.listId,
        item: (await f.items()).first,
      );
      await f.service.clearCheckedItems(f.householdId, f.listId);
      expect((await f.items()).single.name, 'Bread');
    },
  );

  test(
    'List contents are isolated and suggestions deduplicate across lists',
    () async {
      final f = await QaFixture.create();
      await f.add(name: 'Milk');
      await f.service.addGroceryList(
        householdId: f.householdId,
        name: ' Weekend ',
        userId: QaFixture.uid,
      );
      final second =
          (await f.service.watchGroceryLists(f.householdId).first).last;
      expect(second.name, 'Weekend');
      expect(
        await f.service.watchGroceryItems(f.householdId, second.id).first,
        isEmpty,
      );
      await f.service.addGroceryItem(
        householdId: f.householdId,
        listId: second.id,
        name: 'Milk',
        quantity: '1',
        addedBy: QaFixture.uid,
      );
      await f.service.addGroceryItem(
        householdId: f.householdId,
        listId: second.id,
        name: 'Apples',
        quantity: '1',
        addedBy: QaFixture.uid,
      );
      expect(await f.service.watchSmartSuggestions(f.householdId).first, [
        'Apples',
        'Milk',
      ]);
      expect((await f.items()).length, 1);
    },
  );

  test('Independent subscriptions receive added items', () async {
    final f = await QaFixture.create();
    final events = <int>[];
    final subscription = f.service
        .watchGroceryItems(f.householdId, f.listId)
        .listen((items) => events.add(items.length));
    addTearDown(subscription.cancel);
    await Future<void>.delayed(Duration.zero);
    await f.add();
    await Future<void>.delayed(Duration.zero);
    expect(events, containsAllInOrder([0, 1]));
  });

  test('QA-01 Editing an item persists its replacement photo', () async {
    final f = await QaFixture.create();
    await f.add(imageUrl: 'https://example.test/old.png');
    await f.service.updateGroceryItem(
      householdId: f.householdId,
      listId: f.listId,
      item: (await f.items()).single.copyWith(
        imageUrl: 'https://example.test/new.png',
      ),
    );
    expect((await f.items()).single.imageUrl, 'https://example.test/new.png');
  });

  test(
    'QA-02 Client preserves the admin role returned by the server',
    () async {
      final f = await QaFixture.create();
      final service = FirestoreService(
        firestore: f.db,
        acceptInvitation: (_) async => f.householdId,
      );
      await service.joinHousehold(
        inviteCode: f.household!.inviteCode,
        userId: QaFixture.uid,
      );
      expect(
        (await f.service.getUser(QaFixture.uid))!.role,
        UserRole.familyAdmin,
      );
    },
  );

  test('Deleting a list removes its list document', () async {
    final f = await QaFixture.create();
    await f.add();
    final listPath = 'households/${f.householdId}/lists/${f.listId}';
    await f.service.deleteGroceryList(
      householdId: f.householdId,
      listId: f.listId,
    );
    expect((await f.db.doc(listPath).get()).exists, false);
  });

  test(
    'Refreshing an invitation replaces its code and invalidates the previous one',
    () async {
      final f = await QaFixture.create();
      final oldCode = f.household!.inviteCode;
      await f.service.refreshHouseholdInvite(f.householdId);
      final newCode =
          (await f.db.doc('households/${f.householdId}').get())
                  .data()!['inviteCode']
              as String;
      expect(newCode, isNot(oldCode));
      expect((await f.db.doc('inviteCodes/$oldCode').get()).exists, false);
      expect(
        (await f.db.doc('inviteCodes/$newCode').get()).data()!['createdAt'],
        isA<Timestamp>(),
      );
    },
  );
}
