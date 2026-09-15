import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdService {
  static final AdService instance = AdService._();
  AdService._();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    if (!kIsWeb) {
      await MobileAds.instance.initialize();
    }
    _initialized = true;
    debugPrint('AdMob Initialized');
  }

  static String get bannerAdUnitId {
    if (kIsWeb) {
      return ''; // Ads are not supported on web via google_mobile_ads package
    }
    if (kDebugMode) {
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/9214589741' // Your requested Android Test Banner
          : 'ca-app-pub-3940256099942544/2934735716'; // iOS Test Banner
    }
    return Platform.isAndroid
        ? 'ca-app-pub-3588319744110149/2737966637'
        : const String.fromEnvironment('IOS_ADMOB_BANNER_AD_UNIT_ID');
  }
}
