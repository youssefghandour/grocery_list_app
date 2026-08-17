# Grocery List App

Cross-platform Flutter app (iOS, Android, Web) for shared real-time grocery lists powered by Firebase.

## Features

- **Firebase Auth** — Email/password and Google Sign-In
- **Cloud Firestore** — Real-time sync via snapshot listeners
- **Households** — Shared family groups linked by invite code
- **Roles** — `familyAdmin` and `familyMember`
- **Riverpod** — Reactive state management

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── app.dart                  # MaterialApp + routing
├── firebase_options.dart     # Generated Firebase config
├── constants/
├── models/
├── services/
├── providers/
├── screens/
└── widgets/
```

## Setup

1. Install [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.2+).

2. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com).

3. Enable **Authentication** (Email/Password + Google) and **Cloud Firestore**.

4. Install FlutterFire CLI and configure:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```

5. Deploy Firestore security rules:
   ```bash
   firebase deploy --only firestore:rules
   ```

6. Install dependencies and run:
   ```bash
   cd grocery_list_app
   flutter pub get
   flutter run -d chrome    # Web
   flutter run              # Connected device/emulator
   ```

## Firestore Data Model

```
users/{userId}
  email, displayName, role, householdId?, createdAt, updatedAt

households/{householdId}
  name, inviteCode, createdBy, createdAt, updatedAt
  └── items/{itemId}
        name, quantity, isChecked, addedBy, createdAt, updatedAt

inviteCodes/{code}
  householdId, createdAt
```

## User Roles

| Role            | Firestore value  | Permissions                          |
|-----------------|------------------|--------------------------------------|
| Family Admin    | `familyAdmin`    | Create household, rename, delete     |
| Family Member   | `familyMember`   | View/add/edit/check off list items   |

All household members can CRUD grocery items in real time.

## Real-Time Sync

Grocery items use Firestore `.snapshots()` streams. Any write on one device propagates instantly to all other active sessions (iOS, Android, Web) through the `groceryListProvider` Riverpod stream.
