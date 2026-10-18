import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

// ---------------------------------------------------------------------------
// Service providers
// ---------------------------------------------------------------------------

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final firestoreServiceProvider =
    Provider<FirestoreService>((ref) => FirestoreService());

// ---------------------------------------------------------------------------
// Auth state
// ---------------------------------------------------------------------------

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

final currentFirebaseUserProvider = Provider<User?>((ref) {
  return ref.watch(authStateProvider).value;
});

// ---------------------------------------------------------------------------
// App user profile (Firestore-backed)
// ---------------------------------------------------------------------------

final appUserProvider = StreamProvider<AppUser?>((ref) {
  final user = ref.watch(currentFirebaseUserProvider);
  if (user == null) return Stream.value(null);

  return ref.watch(firestoreServiceProvider).watchUser(user.uid);
});

// ---------------------------------------------------------------------------
// Auth controller
// ---------------------------------------------------------------------------

class AuthController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  AuthService get _auth => ref.read(authServiceProvider);
  FirestoreService get _firestore => ref.read(firestoreServiceProvider);

  Future<void> signInWithEmail(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _auth.signInWithEmail(email: email, password: password);
    });
  }

  Future<void> registerWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final credential = await _auth.registerWithEmail(
        email: email,
        password: password,
      );
      final user = credential.user!;
      await user.updateDisplayName(displayName);
      await _firestore.createUserProfile(
        uid: user.uid,
        email: email,
        displayName: displayName,
      );
    });
  }

  Future<void> signInWithGoogle() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final credential = await _auth.signInWithGoogle();
      final user = credential?.user;

      if (user == null) return;

      final existing = await _firestore.getUser(user.uid);
      if (existing == null) {
        await _firestore.createUserProfile(
          uid: user.uid,
          email: user.email ?? '',
          displayName: user.displayName ?? 'User',
          imageUrl: user.photoURL,
        );
      }
    });
  }

  Future<void> signInWithApple() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final credential = await _auth.signInWithApple();
      final user = credential?.user;

      if (user == null) return;

      final existing = await _firestore.getUser(user.uid);
      if (existing == null) {
        final displayName = user.displayName ??
            (user.email != null && user.email!.isNotEmpty
                ? user.email!.split('@').first
                : 'User');
        await _firestore.createUserProfile(
          uid: user.uid,
          email: user.email ?? '',
          displayName: displayName,
          imageUrl: user.photoURL,
        );
      }
    });
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_auth.signOut);
  }

  Future<void> deleteAccount() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final user = _auth.currentUser;
      if (user != null) {
        final uid = user.uid;
        await _firestore.deleteUserProfile(uid);
        await _auth.deleteAccount();
      }
    });
  }

  Future<void> resetPassword(String email) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _auth.sendPasswordResetEmail(email),
    );
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AsyncValue<void>>(AuthController.new);
