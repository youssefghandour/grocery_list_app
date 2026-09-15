import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:na2slna/models/grocery_item_model.dart';
import 'package:na2slna/providers/grocery_list_provider.dart';
import 'package:na2slna/screens/home/widgets/floating_budget_summary.dart';
import 'package:na2slna/services/firestore_service.dart';
import 'package:na2slna/widgets/add_item_dialog.dart';
import 'package:na2slna/widgets/grocery_item_tile.dart';
import 'package:na2slna/widgets/quick_add_bar.dart';
import 'support/qa_fixture.dart';

class FailingAddService extends FirestoreService {
  FailingAddService(FirebaseFirestore db) : super(firestore: db);
  bool rejectWrites = true;
  @override
  Future<void> addGroceryItem({
    required String householdId,
    required String listId,
    required String name,
    required String quantity,
    required String addedBy,
    String category = 'Other',
    String unit = 'pcs',
    double price = 0,
    String? imageUrl,
  }) async {
    if (rejectWrites) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'QA simulated write denial',
      );
    }
    return super.addGroceryItem(
      householdId: householdId,
      listId: listId,
      name: name,
      quantity: quantity,
      addedBy: addedBy,
      category: category,
      unit: unit,
      price: price,
      imageUrl: imageUrl,
    );
  }

  @override
  Future<void> updateGroceryItem({
    required String householdId,
    required String listId,
    required GroceryItem item,
  }) async {
    if (rejectWrites) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    return super.updateGroceryItem(
      householdId: householdId,
      listId: listId,
      item: item,
    );
  }
}

Future<void> openAdd(
  WidgetTester tester,
  QaFixture f, {
  bool editing = false,
}) async {
  final existing = editing ? (await f.items()).single : null;
  await f.container.read(smartSuggestionsProvider.future);
  await f.pump(
    tester,
    Scaffold(
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showAddItemDialog(context, existingItem: existing),
          child: const Text('Open editor'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open editor'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Quick add ignores whitespace', (tester) async {
    final f = await QaFixture.create();
    await f.pump(tester, const Scaffold(body: QuickAddBar()));
    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(await f.items(), isEmpty);
  });
  testWidgets('Quick add saves typed item and clears the field', (
    tester,
  ) async {
    final f = await QaFixture.create();
    await f.pump(tester, const Scaffold(body: QuickAddBar()));
    await tester.enterText(find.byType(TextField), ' QA Apples ');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.done));
    await tester.pumpAndSettle();
    expect((await f.items()).single.name, 'QA Apples');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });
  testWidgets('Add dialog rejects an empty item name', (tester) async {
    final f = await QaFixture.create();
    await openAdd(tester, f);
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('Enter item name'), findsOneWidget);
    expect(await f.items(), isEmpty);
  });
  testWidgets('Add dialog saves quantity, unit, price and category', (
    tester,
  ) async {
    final f = await QaFixture.create();
    await openAdd(tester, f);
    await tester.enterText(find.byType(TextFormField).first, 'QA Bananas');
    await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
    await tester.tap(find.widgetWithText(ChoiceChip, 'kg'));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Produce').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, '12.50');
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    final item = (await f.items()).single;
    expect(item.name, 'QA Bananas');
    expect(item.quantity, '2');
    expect(item.unit, 'kg');
    expect(item.price, 12.5);
    expect(item.category, 'Produce');
    expect(find.byType(AddItemDialog), findsNothing);
  });
  testWidgets('Cancel discards entered item', (tester) async {
    final f = await QaFixture.create();
    await openAdd(tester, f);
    await tester.enterText(find.byType(TextFormField).first, 'Discard me');
    await tester.ensureVisible(find.text('Cancel'));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await f.items(), isEmpty);
  });
  testWidgets('Smart suggestions show previous matching items', (tester) async {
    final f = await QaFixture.create();
    await f.add(name: 'Milk');
    await openAdd(tester, f);
    await tester.enterText(find.byType(TextFormField).first, 'mi');
    await tester.pumpAndSettle();
    expect(find.text('Milk'), findsWidgets);
  });
  testWidgets('Photo action is restricted to Gold users', (tester) async {
    final f = await QaFixture.create(gold: false);
    await openAdd(tester, f);
    expect(find.text('Add Photo'), findsNothing);
  });
  testWidgets('Gold editor exposes the photo action', (tester) async {
    final f = await QaFixture.create(gold: true);
    await openAdd(tester, f);
    expect(find.text('Add Photo'), findsOneWidget);
  });
  testWidgets('Item checkbox changes purchased state', (tester) async {
    final f = await QaFixture.create();
    await f.add();
    await f.pump(
      tester,
      Scaffold(body: GroceryItemTile(item: (await f.items()).single)),
    );
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect((await f.items()).single.isChecked, true);
  });
  testWidgets('Inline plus and minus update quantity', (tester) async {
    final f = await QaFixture.create();
    await f.add(quantity: '2');
    await f.pump(
      tester,
      Scaffold(body: GroceryItemTile(item: (await f.items()).single)),
    );
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(double.parse((await f.items()).single.quantity), 3);
    await f.pump(
      tester,
      Scaffold(body: GroceryItemTile(item: (await f.items()).single)),
    );
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pumpAndSettle();
    expect(double.parse((await f.items()).single.quantity), 2);
  });
  testWidgets(
    'Deleting quantity one requires confirmation and supports cancel',
    (tester) async {
      final f = await QaFixture.create();
      await f.add(quantity: '1');
      await f.pump(
        tester,
        Scaffold(body: GroceryItemTile(item: (await f.items()).single)),
      );
      await tester.tap(find.byIcon(Icons.delete_outline).last);
      await tester.pumpAndSettle();
      expect(find.text('Delete Item?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect((await f.items()).length, 1);
    },
  );
  testWidgets('Budget total multiplies prices by quantities', (tester) async {
    final f = await QaFixture.create();
    await f.add(name: 'Milk', quantity: '2.5', price: 20);
    await f.add(name: 'Bread', quantity: '3', price: 5);
    await f.pump(tester, const Scaffold(body: FloatingBudgetSummary()));
    expect(find.text('2 items in list'), findsOneWidget);
    expect(find.text('65.00 EGP', findRichText: true), findsOneWidget);
  });
  testWidgets('QA-07 Editing an unchanged decimal quantity preserves it', (
    tester,
  ) async {
    final f = await QaFixture.create();
    await f.add(quantity: '3.0');
    await openAdd(tester, f, editing: true);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(double.parse((await f.items()).single.quantity), 3);
  });
  testWidgets('Fractional quantity survives editing and step controls', (
    tester,
  ) async {
    final f = await QaFixture.create();
    await f.add(quantity: '1.25');
    await openAdd(tester, f, editing: true);
    expect(find.text('1.25'), findsOneWidget);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.add));
    await tester.pump();
    expect(find.text('2.25'), findsOneWidget);
    await tester.tap(find.widgetWithIcon(IconButton, Icons.remove));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect((await f.items()).single.quantity, '1.25');
  });
  testWidgets('QA-08 Negative prices are rejected', (tester) async {
    final f = await QaFixture.create();
    await openAdd(tester, f);
    await tester.enterText(find.byType(TextFormField).first, 'Milk');
    await tester.enterText(find.byType(TextFormField).last, '-5');
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(await f.items(), isEmpty);
    expect(find.text('Enter a price of zero or more'), findsOneWidget);
  });
  for (final price in ['NaN', 'Infinity', 'not a price']) {
    testWidgets('Invalid price "$price" stays in the editor for correction', (
      tester,
    ) async {
      final f = await QaFixture.create();
      await openAdd(tester, f);
      await tester.enterText(find.byType(TextFormField).first, 'Milk');
      await tester.enterText(find.byType(TextFormField).last, price);
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(await f.items(), isEmpty);
      expect(find.text('Enter a price of zero or more'), findsOneWidget);
      expect(find.byType(AddItemDialog), findsOneWidget);
    });
  }
  testWidgets('QA-09 Failed add keeps dialog and input available for retry', (
    tester,
  ) async {
    final f = await QaFixture.create(
      serviceFactory: (db) => FailingAddService(db),
    );
    await openAdd(tester, f);
    await tester.enterText(
      find.byType(TextFormField).first,
      'Do not lose this',
    );
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(f.container.read(groceryListControllerProvider).hasError, true);
    expect(find.byType(AddItemDialog), findsOneWidget);
    expect(find.text('Do not lose this'), findsOneWidget);
    expect(
      find.text('Could not save the item. Please try again.'),
      findsOneWidget,
    );
    (f.service as FailingAddService).rejectWrites = false;
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect((await f.items()).single.name, 'Do not lose this');
    expect(find.byType(AddItemDialog), findsNothing);
  });
  testWidgets('Failed edit retains changed fields and retries the update', (
    tester,
  ) async {
    final f = await QaFixture.create(serviceFactory: FailingAddService.new);
    final service = f.service as FailingAddService;
    service.rejectWrites = false;
    await f.add(name: 'Milk');
    service.rejectWrites = true;
    await openAdd(tester, f, editing: true);
    await tester.enterText(find.byType(TextFormField).first, 'Updated milk');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Updated milk'), findsOneWidget);
    expect(
      find.text('Could not save the item. Please try again.'),
      findsOneWidget,
    );
    expect((await f.items()).single.name, 'Milk');
    service.rejectWrites = false;
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect((await f.items()).single.name, 'Updated milk');
    expect(find.byType(AddItemDialog), findsNothing);
  });
  testWidgets('QA-10 Failed quick add preserves typed input', (tester) async {
    final f = await QaFixture.create(
      serviceFactory: (db) => FailingAddService(db),
    );
    await f.pump(tester, const Scaffold(body: QuickAddBar()));
    await tester.enterText(find.byType(TextField), 'Do not lose this');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.done));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Do not lose this',
    );
    expect(
      find.text('Could not add the item. Please try again.'),
      findsOneWidget,
    );
    (f.service as FailingAddService).rejectWrites = false;
    await tester.tap(find.byIcon(Icons.done));
    await tester.pumpAndSettle();
    expect((await f.items()).single.name, 'Do not lose this');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });
  testWidgets('QA-11 An externally assigned category remains editable', (
    tester,
  ) async {
    final f = await QaFixture.create();
    await f.add(category: 'Dairy');
    await openAdd(tester, f, editing: true);
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect((await f.items()).single.category, 'Dairy');
  });
}
