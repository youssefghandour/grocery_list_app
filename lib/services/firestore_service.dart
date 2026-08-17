import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_constants.dart';
import '../constants/user_roles.dart';
import '../models/grocery_item_model.dart';
import '../models/household_model.dart';
import '../models/user_model.dart';

class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final _random = Random.secure();

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection(AppConstants.usersCollection);

  CollectionReference<Map<String, dynamic>> get _households =>
      _firestore.collection(AppConstants.householdsCollection);

  CollectionReference<Map<String, dynamic>> get _inviteCodes =>
      _firestore.collection(AppConstants.inviteCodesCollection);

  // ---------------------------------------------------------------------------
  // Users
  // ---------------------------------------------------------------------------

  Stream<AppUser?> watchUser(String uid) {
    return _users.doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return AppUser.fromFirestore(doc);
    });
  }

  Future<AppUser?> getUser(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists) return null;
    return AppUser.fromFirestore(doc);
  }

  Future<void> createUserProfile({
    required String uid,
    required String email,
    required String displayName,
  }) async {
    final now = DateTime.now();
    final user = AppUser(
      uid: uid,
      email: email,
      displayName: displayName,
      role: UserRole.familyMember,
      createdAt: now,
    );
    await _users.doc(uid).set(user.toFirestore());
  }

  Future<void> updateDisplayName(String uid, String displayName) async {
    await _users.doc(uid).update({
      'displayName': displayName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<AppUser>> watchHouseholdMembers(String householdId) {
    return _users
        .where('householdId', isEqualTo: householdId)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map(AppUser.fromFirestore).toList());
  }

  // ---------------------------------------------------------------------------
  // Households
  // ---------------------------------------------------------------------------

  Stream<Household?> watchHousehold(String householdId) {
    return _households.doc(householdId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Household.fromFirestore(doc);
    });
  }

  Future<Household> createHousehold({
    required String name,
    required String userId,
  }) async {
    final inviteCode = _generateInviteCode();
    final now = DateTime.now();
    final householdRef = _households.doc();

    await _firestore.runTransaction((transaction) async {
      transaction.set(householdRef, {
        'name': name.trim(),
        'inviteCode': inviteCode,
        'createdBy': userId,
        'createdAt': Timestamp.fromDate(now),
      });

      transaction.set(_inviteCodes.doc(inviteCode), {
        'householdId': householdRef.id,
        'createdAt': Timestamp.fromDate(now),
      });

      transaction.update(_users.doc(userId), {
        'householdId': householdRef.id,
        'role': UserRole.familyAdmin.firestoreValue,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    final doc = await householdRef.get();
    return Household.fromFirestore(doc);
  }

  Future<Household> joinHousehold({
    required String inviteCode,
    required String userId,
  }) async {
    final normalizedCode = inviteCode.trim().toUpperCase();
    final inviteDoc = await _inviteCodes.doc(normalizedCode).get();

    if (!inviteDoc.exists) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'invite-not-found',
        message: 'Invalid invite code.',
      );
    }

    final householdId = inviteDoc.data()!['householdId'] as String;
    final householdDoc = await _households.doc(householdId).get();

    if (!householdDoc.exists) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'household-not-found',
        message: 'Household no longer exists.',
      );
    }

    await _users.doc(userId).update({
      'householdId': householdId,
      'role': UserRole.familyMember.firestoreValue,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return Household.fromFirestore(householdDoc);
  }

  Future<void> leaveHousehold(String userId) async {
    await _users.doc(userId).update({
      'householdId': FieldValue.delete(),
      'role': UserRole.familyMember.firestoreValue,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(
      AppConstants.inviteCodeLength,
      (_) => chars[_random.nextInt(chars.length)],
    ).join();
  }

  // ---------------------------------------------------------------------------
  // Grocery items (real-time subcollection)
  // ---------------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _itemsCollection(String householdId) {
    return _households
        .doc(householdId)
        .collection(AppConstants.itemsSubcollection);
  }

  Stream<List<GroceryItem>> watchGroceryItems(String householdId) {
    return _itemsCollection(householdId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map(GroceryItem.fromFirestore).toList());
  }

  Future<void> addGroceryItem({
    required String householdId,
    required String name,
    required String quantity,
    required String addedBy,
  }) async {
    final now = DateTime.now();
    await _itemsCollection(householdId).add({
      'name': name.trim(),
      'quantity': quantity.trim().isEmpty ? '1' : quantity.trim(),
      'isChecked': false,
      'addedBy': addedBy,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });
  }

  Future<void> updateGroceryItem({
    required String householdId,
    required GroceryItem item,
  }) async {
    await _itemsCollection(householdId).doc(item.id).update({
      'name': item.name.trim(),
      'quantity': item.quantity.trim(),
      'isChecked': item.isChecked,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> toggleGroceryItem({
    required String householdId,
    required GroceryItem item,
  }) async {
    await _itemsCollection(householdId).doc(item.id).update({
      'isChecked': !item.isChecked,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteGroceryItem({
    required String householdId,
    required String itemId,
  }) async {
    await _itemsCollection(householdId).doc(itemId).delete();
  }

  Future<void> clearCheckedItems(String householdId) async {
    final snapshot = await _itemsCollection(householdId)
        .where('isChecked', isEqualTo: true)
        .get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
