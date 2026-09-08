import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/household_provider.dart';

final deepLinkServiceProvider = Provider((ref) => DeepLinkService(ref));

class DeepLinkService {
  DeepLinkService(this._ref);
  final Ref _ref;
  
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  GlobalKey<ScaffoldMessengerState>? _messengerKey;

  void initialize(GlobalKey<ScaffoldMessengerState> messengerKey) async {
    _messengerKey = messengerKey;

    // 1. Handle deep link when the app is already open
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      _handleUri(uri);
    });

    // 2. Handle deep link when the app is opened from a terminated state
    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      _handleUri(initialUri);
    }
  }

  void dispose() {
    _linkSubscription?.cancel();
  }

  void _handleUri(Uri uri) {
    debugPrint('DEEP_LINK: Received URI: $uri');
    debugPrint('DEEP_LINK: Scheme: ${uri.scheme}, Host: ${uri.host}, Path: ${uri.path}');
    
    final path = uri.path.replaceAll(RegExp(r'^/|/$'), '');
    
    // Support na2slna://join?code=ABC123 
    // AND https://animemusic-e8c09.web.app/join?code=ABC123
    // AND even na2slna:join?code=ABC123
    bool isJoinLink = (uri.scheme == 'na2slna' && (uri.host == 'join' || path == 'join')) ||
                     (uri.scheme == 'https' && uri.host == 'animemusic-e8c09.web.app' && path == 'join');

    if (isJoinLink) {
      final code = uri.queryParameters['code'];
      debugPrint('DEEP_LINK: Detected join link with code: $code');
      if (code != null && code.length == 6) {
        _waitForAuthAndJoin(code);
      } else {
        debugPrint('DEEP_LINK: Invalid code format: $code');
      }
    } else {
      debugPrint('DEEP_LINK: Not a recognized join link.');
    }
  }

  /// Ensures the user is logged in before attempting to join a household
  void _waitForAuthAndJoin(String code) {
    Timer? timer;
    int attempts = 0;

    timer = Timer.periodic(const Duration(seconds: 1), (t) async {
      attempts++;
      final user = _ref.read(currentFirebaseUserProvider);
      
      if (user != null) {
        timer?.cancel();
        _joinHousehold(code);
      } else if (attempts > 30) {
        // Stop trying after 30 seconds
        timer?.cancel();
        _showSnackBar('Please login first to join the household.');
      }
    });
  }

  Future<void> _joinHousehold(String code) async {
    try {
      _showSnackBar('Joining household $code...');
      
      await _ref.read(householdControllerProvider.notifier).joinHousehold(code);
      
      final error = _ref.read(householdControllerProvider).error;
      if (error != null) {
        _showSnackBar('Failed to join: $error');
      } else {
        _showSnackBar('Welcome! You have joined the household.');
      }
    } catch (e) {
      _showSnackBar('Error: $e');
    }
  }

  void _showSnackBar(String message) {
    _messengerKey?.currentState?.clearSnackBars();
    _messengerKey?.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
