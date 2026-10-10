import 'dart:async';
import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:na2slna/providers/auth_provider.dart';
import 'package:na2slna/services/payment_service.dart';

class IsolatedStore implements InAppPurchase {
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  final completed = <PurchaseDetails>[];
  PurchaseParam? purchaseParam;
  int restores = 0;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async =>
      ProductDetailsResponse(productDetails: [testProduct], notFoundIDs: []);
  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) async {
    this.purchaseParam = purchaseParam;
    return true;
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) async {
    restores++;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected store operation: ${invocation.memberName}',
  );
}

final testProduct = ProductDetails(
  id: PaymentService.goldId,
  title: 'Gold',
  description: 'Isolated test',
  price: 'EGP 150',
  rawPrice: 150,
  currencyCode: 'EGP',
);

PurchaseDetails purchase({PurchaseStatus status = PurchaseStatus.purchased}) =>
    PurchaseDetails(
      productID: PaymentService.goldId,
      purchaseID: 'test-order',
      verificationData: PurchaseVerificationData(
        localVerificationData: 'ignored-client-json',
        serverVerificationData: 'isolated-purchase-token',
        source: 'google_play',
      ),
      transactionDate: '1',
      status: status,
    )..pendingCompletePurchase = true;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late IsolatedStore store;
  late ProviderContainer container;
  late PaymentService service;
  late List<({String name, Map<String, dynamic> data})> calls;
  bool available = true;
  Object? verificationError;
  Map<String, dynamic> verified = {};

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    available = true;
    verificationError = null;
    verified = {'verified': true, 'acknowledged': true};
    store = IsolatedStore();
    calls = [];
    container = ProviderContainer(
      overrides: [
        currentFirebaseUserProvider.overrideWithValue(MockUser(uid: 'buyer')),
        paymentServiceProvider.overrideWith(
          (ref) => PaymentService(
            ref,
            store: store,
            callBackend: (name, data) async {
              calls.add((name: name, data: data));
              if (name == 'getPaymentCapabilities') {
                return {'nativeStore': available};
              }
              if (verificationError != null) throw verificationError!;
              return verified;
            },
          ),
        ),
      ],
    );
    service = container.read(paymentServiceProvider);
    service.initialize();
  });
  tearDown(() async {
    service.dispose();
    container.dispose();
    await store.updates.close();
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'Product lookup identifies Google Play and uses backend availability',
    () async {
      expect(await service.fetchProducts(), [testProduct]);
      expect(calls.single.data, {'source': 'google_play'});
      available = false;
      await expectLater(
        service.buyProduct(testProduct),
        throwsA(isA<PaymentException>()),
      );
      expect(store.purchaseParam, isNull);
    },
  );
  test('iOS product lookup identifies Apple separately', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    available = false;
    await expectLater(
      service.fetchProducts(),
      throwsA(isA<PaymentException>()),
    );
    expect(calls.single.data, {'source': 'app_store'});
  });
  test('Checkout binds purchase to the hashed signed-in account', () async {
    await service.buyProduct(testProduct);
    expect(
      store.purchaseParam!.applicationUserName,
      sha256.convert(utf8.encode('buyer')).toString(),
    );
  });
  for (final status in [PurchaseStatus.purchased, PurchaseStatus.restored]) {
    test(
      '$status sends the actual token to backend and avoids double acknowledgement',
      () async {
        store.updates.add([purchase(status: status)]);
        await pumpEventQueue();
        expect(calls.single.name, 'verifyStorePurchase');
        expect(calls.single.data, {
          'productId': PaymentService.goldId,
          'purchaseId': 'test-order',
          'source': 'google_play',
          'verificationData': 'isolated-purchase-token',
        });
        expect(store.completed, isEmpty);
        expect(container.read(paymentMessageProvider), contains('verified'));
      },
    );
  }
  test(
    'Rejected verification never finishes a purchase and a later restore can retry',
    () async {
      verificationError = FirebaseFunctionsException(
        code: 'unavailable',
        message: 'Temporary outage',
      );
      store.updates.add([purchase()]);
      await pumpEventQueue();
      expect(store.completed, isEmpty);
      expect(
        container.read(paymentMessageProvider),
        contains('could not be verified'),
      );
      verificationError = null;
      store.updates.add([purchase(status: PurchaseStatus.restored)]);
      await pumpEventQueue();
      expect(calls.length, 2);
      expect(
        container.read(paymentMessageProvider),
        contains('Premium features are ready'),
      );
    },
  );
  test('Unverified response never acknowledges a purchase', () async {
    verified = {'verified': false};
    store.updates.add([purchase()]);
    await pumpEventQueue();
    expect(store.completed, isEmpty);
    expect(
      container.read(paymentMessageProvider),
      contains('could not be verified'),
    );
  });
  test(
    'Pending payment waits for Google Play without verification or acknowledgement',
    () async {
      store.updates.add([purchase(status: PurchaseStatus.pending)]);
      await pumpEventQueue();
      expect(calls, isEmpty);
      expect(store.completed, isEmpty);
      expect(
        container.read(paymentMessageProvider),
        contains('awaiting confirmation'),
      );
    },
  );
  test('Restore checks backend availability before contacting store', () async {
    await service.restorePurchases();
    expect(store.restores, 1);
    available = false;
    await expectLater(
      service.restorePurchases(),
      throwsA(isA<PaymentException>()),
    );
    expect(store.restores, 1);
  });
}
