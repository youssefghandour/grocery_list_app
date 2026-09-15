import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:na2slna/providers/grocery_list_provider.dart';
import 'support/qa_fixture.dart';

void main() {
  test('Controller adds item with selected category, unit and price', () async {
    final f = await QaFixture.create();
    await f.container
        .read(groceryListControllerProvider.notifier)
        .addItem(
          name: 'Apples',
          quantity: '3',
          category: 'Produce',
          unit: 'kg',
          price: 15,
        );
    final item = (await f.items()).single;
    expect(item.name, 'Apples');
    expect(item.category, 'Produce');
    expect(item.unit, 'kg');
    expect(item.price, 15);
  });

  test(
    'Duplicate item names merge case-insensitively and retain existing price',
    () async {
      final f = await QaFixture.create();
      await f.add(name: 'Milk', quantity: '2', price: 30);
      await f.container
          .read(groceryListControllerProvider.notifier)
          .addItem(name: ' MILK ', quantity: '3');
      final item = (await f.items()).single;
      expect(item.quantity, '5');
      expect(item.price, 30);
      expect(item.category, 'Dairy & Eggs');
    },
  );

  test('Selecting a list directs new items to that list only', () async {
    final f = await QaFixture.create();
    final firstList = f.listId;
    await f.container
        .read(groceryListControllerProvider.notifier)
        .addList('Weekend');
    await f.refresh();
    final second =
        (await f.service.watchGroceryLists(f.householdId).first).last.id;
    f.container.read(selectedListIdProvider.notifier).set(second);
    await f.container.read(groceryListProvider.future);
    await f.container
        .read(groceryListControllerProvider.notifier)
        .addItem(name: 'Bread', quantity: '1');
    expect(
      await f.service.watchGroceryItems(f.householdId, firstList).first,
      isEmpty,
    );
    expect((await f.items()).single.name, 'Bread');
  });

  test('Checked and unchecked projections separate purchased items', () async {
    final f = await QaFixture.create();
    await f.add(name: 'Milk');
    await f.add(name: 'Bread');
    await f.container
        .read(groceryListControllerProvider.notifier)
        .toggleItem((await f.items()).first);
    await f.refresh();
    expect(f.container.read(checkedItemsProvider).single.name, 'Milk');
    expect(f.container.read(uncheckedItemsProvider).single.name, 'Bread');
  });

  test('No household yields empty lists and adding does not write', () async {
    final f = await QaFixture.create(withHousehold: false);
    expect(f.container.read(activeListIdProvider), isNull);
    await f.container
        .read(groceryListControllerProvider.notifier)
        .addItem(name: 'Milk', quantity: '1');
    expect((await f.db.collectionGroup('items').get()).docs, isEmpty);
  });

  test('QA-04 Duplicate decimal quantities add numerically', () async {
    final f = await QaFixture.create();
    await f.add(quantity: '2.0');
    await f.container
        .read(groceryListControllerProvider.notifier)
        .addItem(name: 'Milk', quantity: '1.0');
    expect(double.parse((await f.items()).single.quantity), 3);
  });

  test(
    'Duplicate fractional quantities retain their fractional portion',
    () async {
      final f = await QaFixture.create();
      await f.add(quantity: '0.25');
      await f.container
          .read(groceryListControllerProvider.notifier)
          .addItem(name: 'Milk', quantity: '1.5');
      expect(double.parse((await f.items()).single.quantity), 1.75);
    },
  );

  for (final invalidPrice in [-1.0, double.nan, double.infinity]) {
    test('Controller rejects invalid price $invalidPrice', () async {
      final f = await QaFixture.create();
      await f.container
          .read(groceryListControllerProvider.notifier)
          .addItem(name: 'Milk', quantity: '1', price: invalidPrice);
      expect(f.container.read(groceryListControllerProvider).hasError, true);
      expect(await f.items(), isEmpty);
    });
  }

  test(
    'QA-05 Stale selected list falls back to a valid household list',
    () async {
      final f = await QaFixture.create();
      final validId = f.listId;
      f.container
          .read(selectedListIdProvider.notifier)
          .set('deleted-or-previous-household-list');
      expect(f.container.read(activeListIdProvider), validId);
      await f.container
          .read(groceryListControllerProvider.notifier)
          .addItem(name: 'Still in this household', quantity: '1');
      expect((await f.items()).single.name, 'Still in this household');
      expect(
        (await f.db.collectionGroup('items').get())
            .docs
            .single
            .reference
            .parent
            .parent!
            .id,
        validId,
      );
    },
  );

  test(
    'QA-06 First add to a legacy household creates a list and keeps the item',
    () async {
      final f = await QaFixture.create();
      await f.db.doc('households/${f.householdId}/lists/${f.listId}').delete();
      await f.refresh();
      await f.container
          .read(groceryListControllerProvider.notifier)
          .addItem(name: 'First item', quantity: '1');
      final stored = await f.db.collectionGroup('items').get();
      expect(stored.docs.length, 1);
    },
  );
}
