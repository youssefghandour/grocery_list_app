import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../constants/app_constants.dart';
import '../constants/user_roles.dart';
import '../models/grocery_item_model.dart';
import '../models/grocery_list_model.dart';
import '../models/household_model.dart';
import '../models/recurring_list_template_model.dart';
import '../models/user_model.dart';

class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore, this.acceptInvitation})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final Future<String> Function(String inviteCode)? acceptInvitation;
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
    String? imageUrl,
  }) async {
    final now = DateTime.now();
    final user = AppUser(
      uid: uid,
      email: email,
      displayName: displayName,
      role: UserRole.familyMember,
      imageUrl: imageUrl,
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

  Future<void> updateFcmToken(String uid, String? token) async {
    await _users.doc(uid).update({
      'fcmToken': token,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateNotificationPreference(String uid, bool enabled) async {
    await _users.doc(uid).update({
      'notificationsEnabled': enabled,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteUserProfile(String uid) async {
    await _users.doc(uid).delete();
  }

  Stream<List<AppUser>> watchHouseholdMembers(String householdId) {
    return _users
        .where('householdId', isEqualTo: householdId)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(AppUser.fromFirestore).toList());
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

  Future<void> updateHouseholdName(String householdId, String newName) async {
    await _households.doc(householdId).update({'name': newName.trim()});
  }

  Future<Household> createHousehold({
    required String name,
    required String userId,
  }) async {
    if (name.trim().isEmpty || name.trim().length > 120) {
      throw ArgumentError('Enter a household name of 1 to 120 characters.');
    }
    final inviteCode = _generateInviteCode();
    final householdRef = _households.doc();

    await _firestore.runTransaction((transaction) async {
      transaction.set(householdRef, {
        'name': name.trim(),
        'inviteCode': inviteCode,
        'createdBy': userId,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Create a default list for the new household
      final defaultListRef = householdRef
          .collection(AppConstants.listsSubcollection)
          .doc();
      transaction.set(defaultListRef, {
        'name': 'Main List',
        'createdBy': userId,
        'createdAt': FieldValue.serverTimestamp(),
        'isDefault': true,
      });

      transaction.set(_inviteCodes.doc(inviteCode), {
        'householdId': householdRef.id,
        'createdAt': FieldValue.serverTimestamp(),
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
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(normalizedCode)) {
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: 'invite-not-found',
        message: 'Invalid invite code.',
      );
    }
    try {
      // The server derives identity from Firebase Auth. Never send a claimed UID.
      final String householdId;
      if (acceptInvitation != null) {
        householdId = await acceptInvitation!(normalizedCode);
      } else {
        final result =
            await FirebaseFunctions.instanceFor(region: 'us-central1')
                .httpsCallable('joinHousehold')
                .call<Map<String, dynamic>>({'inviteCode': normalizedCode});
        householdId = result.data['householdId'] as String;
      }
      final householdDoc = await _households.doc(householdId).get();
      if (!householdDoc.exists) {
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'household-not-found',
          message: 'Household no longer exists.',
        );
      }
      return Household.fromFirestore(householdDoc);
    } on FirebaseFunctionsException catch (error) {
      final details = error.details;
      throw FirebaseException(
        plugin: 'cloud_firestore',
        code: details is Map && details['reason'] is String
            ? details['reason'] as String
            : error.code,
        message:
            error.message ?? 'Unable to join this household. Please retry.',
      );
    }
  }

  Future<void> refreshHouseholdInvite(String householdId) async {
    final householdRef = _households.doc(householdId);
    final newCode = _generateInviteCode();
    await _firestore.runTransaction((transaction) async {
      final household = await transaction.get(householdRef);
      if (!household.exists) throw StateError('Household no longer exists.');
      final oldCode = household.data()!['inviteCode'] as String;
      transaction.set(_inviteCodes.doc(newCode), {
        'householdId': householdId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.update(householdRef, {
        'inviteCode': newCode,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (oldCode != newCode) transaction.delete(_inviteCodes.doc(oldCode));
    });
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
  // Grocery Lists
  // ---------------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _listsCollection(
    String householdId,
  ) {
    return _households
        .doc(householdId)
        .collection(AppConstants.listsSubcollection);
  }

  Stream<List<GroceryList>> watchGroceryLists(String householdId) {
    return _listsCollection(householdId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(GroceryList.fromFirestore).toList(),
        );
  }

  Future<void> addGroceryList({
    required String householdId,
    required String name,
    required String userId,
  }) async {
    if (name.trim().isEmpty || name.trim().length > 120) {
      throw ArgumentError('Enter a shopping list name of 1 to 120 characters.');
    }
    final now = DateTime.now();
    await _listsCollection(householdId).add({
      'name': name.trim(),
      'createdBy': userId,
      'createdAt': Timestamp.fromDate(now),
      'isDefault': false,
    });
  }

  CollectionReference<Map<String, dynamic>> _templatesCollection(
    String householdId,
  ) {
    return _households.doc(householdId).collection('listTemplates');
  }

  Stream<List<RecurringListTemplate>> watchRecurringListTemplates(
    String householdId,
  ) {
    return _templatesCollection(householdId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(RecurringListTemplate.fromFirestore).toList(),
        );
  }

  Future<void> saveRecurringListTemplate({
    required String householdId,
    required String name,
    required String userId,
    required List<GroceryItem> items,
  }) async {
    if (name.trim().isEmpty || name.trim().length > 120) {
      throw ArgumentError('Enter a saved list name of 1 to 120 characters.');
    }
    if (items.isEmpty || items.length > 100) {
      throw ArgumentError('A saved list must contain 1 to 100 items.');
    }

    final template = RecurringListTemplate(
      id: '',
      name: name.trim(),
      items: items
          .where((item) => !item.isChecked)
          .map(
            (item) => RecurringListTemplateItem(
              name: item.name,
              quantity: item.quantity,
              category: item.category,
              unit: item.unit,
              price: item.price,
              imageUrl: item.imageUrl,
            ),
          )
          .toList(),
      createdBy: userId,
      createdAt: DateTime.now(),
    );
    if (template.items.isEmpty) {
      throw ArgumentError('Add at least one unchecked item to save this list.');
    }
    await _templatesCollection(householdId).add(template.toFirestore());
  }

  Future<void> deleteRecurringListTemplate({
    required String householdId,
    required String templateId,
  }) async {
    await _templatesCollection(householdId).doc(templateId).delete();
  }

  Future<void> deleteGroceryList({
    required String householdId,
    required String listId,
  }) async {
    // Note: In production, you'd also want to delete all items in this list
    await _listsCollection(householdId).doc(listId).delete();
  }

  // ---------------------------------------------------------------------------
  // Grocery items (nested under lists)
  // ---------------------------------------------------------------------------

  CollectionReference<Map<String, dynamic>> _itemsCollection(
    String householdId,
    String listId,
  ) {
    return _listsCollection(
      householdId,
    ).doc(listId).collection(AppConstants.itemsSubcollection);
  }

  Stream<List<GroceryItem>> watchGroceryItems(
    String householdId,
    String listId,
  ) {
    return _itemsCollection(householdId, listId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map(GroceryItem.fromFirestore).toList(),
        );
  }

  Future<void> addGroceryItem({
    required String householdId,
    required String listId,
    required String name,
    required String quantity,
    required String addedBy,
    String category = 'Other',
    String unit = 'pcs',
    double price = 0.0,
    String? imageUrl,
  }) async {
    final now = DateTime.now();
    await _itemsCollection(householdId, listId).add({
      'householdId': householdId, // Added for collectionGroup suggestions
      'name': name.trim(),
      'quantity': quantity.trim().isEmpty ? '1.0' : quantity.trim(),
      'isChecked': false,
      'addedBy': addedBy,
      'category': category,
      'unit': unit,
      'price': price,
      'imageUrl': imageUrl,
      'isDeal': false,
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });
  }

  Future<void> updateGroceryItem({
    required String householdId,
    required String listId,
    required GroceryItem item,
  }) async {
    await _itemsCollection(householdId, listId).doc(item.id).update({
      'name': item.name.trim(),
      'quantity': item.quantity.trim(),
      'isChecked': item.isChecked,
      'category': item.category,
      'unit': item.unit,
      'price': item.price,
      'imageUrl': item.imageUrl,
      'isDeal': item.isDeal,
      'originalPrice': item.originalPrice,
      'store': item.store,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Map<String, dynamic>?> getCarrefourProductPreference({
    required String householdId,
    required String itemName,
    required String unit,
  }) async {
    final preferenceId = _carrefourPreferenceId(itemName, unit);
    final snapshot = await _households
        .doc(householdId)
        .collection('carrefourProductPreferences')
        .doc(preferenceId)
        .get();
    return snapshot.data();
  }

  Future<void> applyCarrefourProductSelection({
    required String householdId,
    required String listId,
    required GroceryItem item,
    required String selectedBy,
    required String productId,
    required String productName,
    String? brand,
    String? url,
  }) async {
    final normalizedName = item.name.trim().toLowerCase();
    final normalizedUnit = item.unit.trim().toLowerCase();
    final preferenceRef = _households
        .doc(householdId)
        .collection('carrefourProductPreferences')
        .doc(_carrefourPreferenceId(item.name, item.unit));
    final itemRef = _itemsCollection(householdId, listId).doc(item.id);
    final batch = _firestore.batch();

    batch.update(itemRef, {
      'name': item.name.trim(),
      'quantity': item.quantity.trim(),
      'isChecked': item.isChecked,
      'category': item.category,
      'unit': item.unit,
      'price': item.price,
      'imageUrl': item.imageUrl,
      'isDeal': item.isDeal,
      'originalPrice': item.originalPrice,
      'store': 'Carrefour',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(preferenceRef, {
      'itemName': normalizedName,
      'unit': normalizedUnit,
      'productId': productId,
      'productName': productName,
      'brand': brand,
      'url': url,
      'updatedBy': selectedBy,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  String _carrefourPreferenceId(String itemName, String unit) =>
      base64Url.encode(
        utf8.encode(
          '${itemName.trim().toLowerCase()}|${unit.trim().toLowerCase()}',
        ),
      );

  Future<void> toggleGroceryItem({
    required String householdId,
    required String listId,
    required GroceryItem item,
  }) async {
    await _itemsCollection(householdId, listId).doc(item.id).update({
      'isChecked': !item.isChecked,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteGroceryItem({
    required String householdId,
    required String listId,
    required String itemId,
  }) async {
    await _itemsCollection(householdId, listId).doc(itemId).delete();
  }

  Future<void> clearCheckedItems(String householdId, String listId) async {
    final snapshot = await _itemsCollection(
      householdId,
      listId,
    ).where('isChecked', isEqualTo: true).get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  // ---------------------------------------------------------------------------
  // Smart Suggestions
  // ---------------------------------------------------------------------------

  /// Fetches unique item names previously added by the household for suggestions.
  Stream<List<String>> watchSmartSuggestions(String householdId) {
    // In a large app, we'd use a separate 'history' collection.
    // For now, we'll query items across all lists in the household.
    // Note: Firestore doesn't support 'distinct' queries well, so we'll process in-memory
    // or just query a few recent items.
    return _firestore
        .collectionGroup(AppConstants.itemsSubcollection)
        .where(
          'householdId',
          isEqualTo: householdId,
        ) // We'd need to add this field to items for efficient group query
        .limit(50)
        .snapshots()
        .map((snapshot) {
          final names = snapshot.docs
              .map((doc) => doc.data()['name'] as String)
              .toSet()
              .toList();
          names.sort();
          return names;
        });
  }
}
