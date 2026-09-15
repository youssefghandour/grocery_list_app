import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:na2slna/screens/settings/upgrade_screen.dart';
import 'package:na2slna/services/payment_service.dart';

class LocalPaymentService implements PaymentService {
  List<ProductDetails> products = [];
  Object? fetchError;
  Object? restoreError;
  Object? buyError;
  String? purchasedId;
  bool restored = false;
  @override
  Future<List<ProductDetails>> fetchProducts() async {
    if (fetchError != null) throw fetchError!;
    return products;
  }

  @override
  Future<void> buyProduct(ProductDetails product) async {
    if (buyError != null) throw buyError!;
    purchasedId = product.id;
  }

  @override
  Future<void> restorePurchases() async {
    if (restoreError != null) throw restoreError!;
    restored = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected payment operation');
}

ProductDetails product(String id, double price) => ProductDetails(
  id: id,
  title: id,
  description: 'Local QA',
  price: '$price EGP',
  rawPrice: price,
  currencyCode: 'EGP',
);

void main() {
  Future<void> pump(WidgetTester tester, LocalPaymentService payments) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1100);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [paymentServiceProvider.overrideWithValue(payments)],
        child: const MaterialApp(home: UpgradeScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('Store plans show the returned product prices', (tester) async {
    final p = LocalPaymentService()
      ..products = [
        product(PaymentService.proId, 75),
        product(PaymentService.goldId, 150),
      ];
    await pump(tester, p);
    expect(find.text('75.0 EGP'), findsOneWidget);
    expect(find.text('150.0 EGP'), findsOneWidget);
    await tester.tap(find.text('Family Gold'));
    await tester.pump();
    expect(p.purchasedId, PaymentService.goldId);
  });
  testWidgets('Unavailable store displays a no-products message', (
    tester,
  ) async {
    await pump(tester, LocalPaymentService());
    expect(find.text('No products found in store.'), findsOneWidget);
  });
  testWidgets('Restore purchases invokes the store adapter', (tester) async {
    final p = LocalPaymentService();
    await pump(tester, p);
    await tester.ensureVisible(find.text('Restore Purchases'));
    await tester.tap(find.text('Restore Purchases'));
    await tester.pumpAndSettle();
    expect(p.restored, true);
    expect(find.text('Restoring purchases... Please wait.'), findsOneWidget);
  });
  testWidgets('PAY-05 Store returning only one product must not crash', (
    tester,
  ) async {
    await pump(
      tester,
      LocalPaymentService()..products = [product(PaymentService.proId, 75)],
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Basic Pro'), findsOneWidget);
  });
  testWidgets(
    'PAY-06 Store lookup failure is handled without an uncaught exception',
    (tester) async {
      await pump(
        tester,
        LocalPaymentService()
          ..fetchError = StateError('Local store unavailable'),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
  testWidgets('PAY-07 Restore failure clears loading and reports an error', (
    tester,
  ) async {
    await pump(
      tester,
      LocalPaymentService()..restoreError = StateError('Local restore failure'),
    );
    await tester.ensureVisible(find.text('Restore Purchases'));
    await tester.tap(find.text('Restore Purchases'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text('Could not restore purchases. Please try again.'),
      findsOneWidget,
    );
  });

  testWidgets('Store lookup can recover with Retry after a temporary failure', (
    tester,
  ) async {
    final p = LocalPaymentService()..fetchError = StateError('Offline');
    await pump(tester, p);
    expect(
      find.text('Could not load plans. Please try again.'),
      findsOneWidget,
    );
    p.fetchError = null;
    p.products = [product(PaymentService.goldId, 150)];
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Family Gold'), findsOneWidget);
    expect(find.text('Basic Pro'), findsNothing);
    expect(find.text('Retry'), findsNothing);
    await tester.tap(find.text('Family Gold'));
    await tester.pumpAndSettle();
    expect(p.purchasedId, PaymentService.goldId);
  });

  testWidgets(
    'Purchase initiation failure leaves plans usable and reports the error',
    (tester) async {
      final p = LocalPaymentService()
        ..products = [product(PaymentService.proId, 75)]
        ..buyError = StateError('Store offline');
      await pump(tester, p);
      await tester.tap(find.text('Basic Pro'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        find.text('Could not start your purchase. Please try again.'),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsNothing);
      p.buyError = null;
      await tester.tap(find.text('Basic Pro'));
      await tester.pumpAndSettle();
      expect(p.purchasedId, PaymentService.proId);
    },
  );
}
