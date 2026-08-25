class AppConstants {
  AppConstants._();

  static const String usersCollection = 'users';
  static const String householdsCollection = 'households';
  static const String listsSubcollection = 'lists';
  static const String itemsSubcollection = 'items';
  static const String inviteCodesCollection = 'inviteCodes';

  static const int inviteCodeLength = 6;

  static const List<String> categories = [
    'Produce',
    'Dairy & Eggs',
    'Bakery',
    'Meat & Seafood',
    'Frozen Foods',
    'Pantry',
    'Beverages',
    'Household',
    'Personal Care',
    'Other',
  ];

  static const List<String> units = [
    'pcs',
    'kg',
    'g',
    'lb',
    'oz',
    'L',
    'ml',
    'pack',
    'box',
    'bag',
    'bottle',
    'can',
  ];
}
