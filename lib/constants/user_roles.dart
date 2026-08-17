/// Role mapping for household members.
enum UserRole {
  familyAdmin('familyAdmin', 'Family Admin'),
  familyMember('familyMember', 'Family Member');

  const UserRole(this.firestoreValue, this.label);

  final String firestoreValue;
  final String label;

  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (role) => role.firestoreValue == value,
      orElse: () => UserRole.familyMember,
    );
  }

  bool get isAdmin => this == UserRole.familyAdmin;
}
