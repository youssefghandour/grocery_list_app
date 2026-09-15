import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:na2slna/providers/auth_provider.dart';
import 'package:na2slna/services/auth_service.dart';
import 'package:na2slna/services/firestore_service.dart';

class LocalGoogleSignIn implements GoogleSignIn {
  bool signedOut = false;
  @override
  Future<void> signOut() async {
    signedOut = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected Google API: ${invocation.memberName}');
}

void main() {
  test(
    'Email registration creates both auth user and Firestore profile',
    () async {
      final db = FakeFirebaseFirestore();
      final auth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'new-user', email: 'new@example.test'),
      );
      final container = ProviderContainer(
        overrides: [
          authServiceProvider.overrideWithValue(AuthService(auth: auth)),
          firestoreServiceProvider.overrideWithValue(
            FirestoreService(firestore: db),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(authControllerProvider.notifier)
          .registerWithEmail(
            email: 'new@example.test',
            password: 'LocalTest123!',
            displayName: 'New User',
          );
      expect(container.read(authControllerProvider).error, isNull);
      final stored = await db.doc('users/${auth.currentUser!.uid}').get();
      expect(stored.data()!['displayName'], 'New User');
      expect(stored.data()!['isGold'], false);
      expect(stored.data()!['role'], 'familyMember');
    },
  );
  test('Email sign-in uses Firebase Auth and exposes current user', () async {
    final auth = MockFirebaseAuth(
      mockUser: MockUser(uid: 'signed-in', email: 'qa@example.test'),
    );
    final service = AuthService(auth: auth);
    await service.signInWithEmail(
      email: ' qa@example.test ',
      password: 'LocalTest123!',
    );
    expect(service.currentUser!.uid, 'signed-in');
  });
  test('Sign out clears Firebase and Google sessions', () async {
    final auth = MockFirebaseAuth(signedIn: true);
    final google = LocalGoogleSignIn();
    final service = AuthService(auth: auth, googleSignIn: google);
    await service.signOut();
    expect(service.currentUser, isNull);
    expect(google.signedOut, true);
  });
  test('Missing Firestore profile returns null', () async {
    final service = FirestoreService(firestore: FakeFirebaseFirestore());
    expect(await service.getUser('missing'), isNull);
  });
}
