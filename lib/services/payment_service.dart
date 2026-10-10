import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';

final paymentServiceProvider = Provider((ref) {
  final service = PaymentService(ref);
  ref.onDispose(service.dispose);
  return service;
});
final paymentMessageProvider = NotifierProvider<PaymentMessage, String?>(
  PaymentMessage.new,
);

class PaymentMessage extends Notifier<String?> {
  @override
  String? build() => null;
  void show(String message) => state = message;
}

class PaymentException implements Exception {
  const PaymentException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PaymentService {
  PaymentService(
    this._ref, {
    InAppPurchase? store,
    Future<dynamic> Function(String, Map<String, dynamic>)? callBackend,
  }) : _iap = store ?? InAppPurchase.instance,
       _callBackend = callBackend ?? _defaultBackendCall;
  final Ref _ref;
  final InAppPurchase _iap;
  final Future<dynamic> Function(String, Map<String, dynamic>) _callBackend;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Future<void> _purchaseQueue = Future.value();
  bool _disposed = false;

  static const String proId = 'na2slna_pro_lifetime';
  static const String goldId = 'na2slna_gold_lifetime';
  static const _unavailable =
      'Purchases are temporarily unavailable. Please try again later.';
  static Future<dynamic> _defaultBackendCall(
    String name,
    Map<String, dynamic> data,
  ) async => (await FirebaseFunctions.instanceFor(
    region: 'us-central1',
  ).httpsCallable(name).call(data)).data;

  void initialize() {
    if (kIsWeb || _subscription != null || _disposed) return;
    _subscription = _iap.purchaseStream.listen(
      (purchases) {
        _purchaseQueue = _purchaseQueue.then(
          (_) => _listenToPurchaseUpdated(purchases),
        );
      },
      onError: (_) => _message(
        'Could not process your purchase. Please try restoring purchases.',
      ),
    );
  }

  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _subscription = null;
  }

  void _message(String message) {
    if (!_disposed) _ref.read(paymentMessageProvider.notifier).show(message);
  }

  Future<void> _requireStoreVerification() async {
    if (_ref.read(currentFirebaseUserProvider) == null) {
      throw const PaymentException('Please sign in before purchasing.');
    }
    try {
      final result = await _callBackend('getPaymentCapabilities', {
        'source': defaultTargetPlatform == TargetPlatform.android
            ? 'google_play'
            : 'app_store',
      });
      if (result is! Map || result['nativeStore'] != true) {
        throw const PaymentException(_unavailable);
      }
    } on FirebaseFunctionsException {
      throw const PaymentException(_unavailable);
    }
  }

  Future<List<ProductDetails>> fetchProducts() async {
    // Never offer a charge until the server can verify store receipts.
    await _requireStoreVerification();
    if (!await _iap.isAvailable()) return [];
    final response = await _iap.queryProductDetails({proId, goldId});
    if (response.error != null) {
      throw const PaymentException('Could not load plans. Please try again.');
    }
    return response.productDetails;
  }

  Future<void> buyProduct(ProductDetails product) async {
    if (![proId, goldId].contains(product.id)) {
      throw const PaymentException('Choose a valid plan.');
    }
    await _requireStoreVerification();
    final uid = _ref.read(currentFirebaseUserProvider)?.uid;
    if (uid == null) {
      throw const PaymentException('Please sign in before purchasing.');
    }
    final started = await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(
        productDetails: product,
        applicationUserName: sha256.convert(utf8.encode(uid)).toString(),
      ),
    );
    if (!started) {
      throw const PaymentException(
        'Could not start your purchase. Please try again.',
      );
    }
  }

  Future<void> restorePurchases() async {
    await _requireStoreVerification();
    await _iap.restorePurchases();
  }

  Future<void> startPaymobCheckout(
    BuildContext context,
    String planType,
  ) async {
    // Store-distributed native apps use their store's billing flow.
    if (!kIsWeb) throw const PaymentException(_unavailable);
    if (_ref.read(currentFirebaseUserProvider) == null) {
      throw const PaymentException('Please sign in before purchasing.');
    }
    if (!['pro', 'gold'].contains(planType)) {
      throw const PaymentException('Choose a valid plan.');
    }
    try {
      final data = await _callBackend('createPaymobOrder', {
        'planType': planType,
      });
      if (data is! Map ||
          data['clientSecret'] is! String ||
          data['publicKey'] is! String) {
        throw const PaymentException(
          'Could not open checkout. Please try again.',
        );
      }
      final url = Uri.https('accept.paymob.com', '/unifiedcheckout/', {
        'publicKey': data['publicKey'] as String,
        'clientSecret': data['clientSecret'] as String,
      });
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw const PaymentException(
          'Could not open checkout. Please try again.',
        );
      }
    } on FirebaseFunctionsException {
      throw const PaymentException(_unavailable);
    }
  }

  Future<void> _listenToPurchaseUpdated(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (_disposed) return;
      if (purchase.status == PurchaseStatus.pending) {
        _message('Your purchase is awaiting confirmation.');
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        _message('Your purchase could not be completed. Please try again.');
        continue;
      }
      if (purchase.status != PurchaseStatus.purchased &&
          purchase.status != PurchaseStatus.restored) {
        continue;
      }
      try {
        if (_ref.read(currentFirebaseUserProvider) == null ||
            ![proId, goldId].contains(purchase.productID)) {
          throw const PaymentException('Sign in to restore your purchase.');
        }
        final result = await _callBackend('verifyStorePurchase', {
          'productId': purchase.productID,
          'purchaseId': purchase.purchaseID,
          'source': purchase.verificationData.source,
          'verificationData': purchase.verificationData.serverVerificationData,
        });
        if (result is! Map || result['verified'] != true) {
          throw const PaymentException(
            'Your purchase could not be verified. Please try restoring it later.',
          );
        }
        // The server alone writes entitlements. Finish only a verified purchase.
        if (purchase.pendingCompletePurchase &&
            !(purchase.verificationData.source == 'google_play' &&
                result['acknowledged'] == true)) {
          await _iap.completePurchase(purchase);
        }
        _message('Your purchase is verified. Premium features are ready.');
      } catch (_) {
        _message(
          'Your purchase could not be verified. Please try restoring it later.',
        );
      }
    }
  }
}
