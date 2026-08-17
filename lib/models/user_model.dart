import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/user_roles.dart';

class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    this.householdId,
    required this.createdAt,
    this.updatedAt,
  });

  final String uid;
  final String email;
  final String displayName;
  final UserRole role;
  final String? householdId;
  final DateTime createdAt;
  final DateTime? updatedAt;

  bool get hasHousehold => householdId != null && householdId!.isNotEmpty;

  factory AppUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return AppUser(
      uid: doc.id,
      email: data['email'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      role: UserRole.fromString(data['role'] as String? ?? 'familyMember'),
      householdId: data['householdId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'email': email,
      'displayName': displayName,
      'role': role.firestoreValue,
      if (householdId != null) 'householdId': householdId,
      'createdAt': Timestamp.fromDate(createdAt),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  AppUser copyWith({
    String? displayName,
    UserRole? role,
    String? householdId,
    DateTime? updatedAt,
  }) {
    return AppUser(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      householdId: householdId ?? this.householdId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
