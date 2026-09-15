import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:na2slna/providers/auth_provider.dart';
import 'package:na2slna/providers/household_provider.dart';
import 'package:na2slna/providers/settings_provider.dart';
import 'package:na2slna/screens/home/home_screen.dart';
import 'package:na2slna/screens/home/views/list_tab_view.dart';
import 'package:na2slna/screens/home/views/profile_tab_view.dart';
import 'package:na2slna/screens/home/widgets/household_widgets.dart';
import 'package:na2slna/widgets/add_item_dialog.dart';
import 'package:na2slna/widgets/error_screen.dart';
import 'package:na2slna/widgets/onboarding_screen.dart';
import 'package:na2slna/widgets/qr_dialog.dart';
import 'package:na2slna/widgets/banner_ad_widget.dart';
import 'package:na2slna/services/firestore_service.dart';
import 'support/qa_fixture.dart';

class FailingListService extends FirestoreService {
  FailingListService(FakeFirebaseFirestore db) : super(firestore: db);

  @override
  Future<void> addGroceryList({
    required String householdId,
    required String name,
    required String userId,
  }) async {
    throw StateError('Simulated list write failure');
  }
}

class ControlledInviteService extends FirestoreService {
  ControlledInviteService(FakeFirebaseFirestore db) : super(firestore: db);

  final releaseRefresh = Completer<void>();
  bool rejectRefresh = true;
  int refreshCalls = 0;

  @override
  Future<void> refreshHouseholdInvite(String householdId) async {
    refreshCalls++;
    await releaseRefresh.future;
    if (rejectRefresh) throw StateError('Simulated refresh failure');
    return super.refreshHouseholdInvite(householdId);
  }
}

Future<QaFixture> familyGoldFixture() async {
  final f = await QaFixture.create(pro: false);
  await f.db.doc('users/gold-admin').set({
    'displayName': 'Gold Admin',
    'householdId': f.householdId,
    'role': 'familyAdmin',
    'isGold': true,
  });
  await f.db.doc('households/${f.householdId}').update({
    'createdBy': 'gold-admin',
  });
  await f.db.doc('users/${QaFixture.uid}').update({'role': 'familyMember'});
  f.container.listen(householdProvider, (_, _) {});
  f.container.listen(householdMembersProvider, (_, _) {});
  await f.container.read(householdProvider.future);
  await f.container.read(householdMembersProvider.future);
  await f.container.read(appUserProvider.future);
  return f;
}

void main() {
  testWidgets('Home navigates between list, household and profile tabs', (
    tester,
  ) async {
    final f = await QaFixture.create();
    await f.pump(tester, const HomeScreen());
    expect(find.text('Main List'), findsOneWidget);
    await tester.tap(find.text('Household').last);
    await tester.pumpAndSettle();
    expect(find.text('Household Settings'), findsOneWidget);
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    expect(find.text('Profile & Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('New user sees create-or-join onboarding', (tester) async {
    final f = await QaFixture.create(withHousehold: false);
    await f.pump(tester, const HomeScreen());
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('Create New Household'), findsOneWidget);
    expect(find.text('Join Existing via Code or QR'), findsOneWidget);
  });
  testWidgets('Profile edit saves display name', (tester) async {
    final f = await QaFixture.create();
    final user = await f.service.getUser(QaFixture.uid);
    await f.pump(tester, ProfileTabView(appUser: user!));
    await tester.ensureVisible(find.byIcon(Icons.edit_outlined));
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Updated QA Name');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      (await f.service.getUser(QaFixture.uid))!.displayName,
      'Updated QA Name',
    );
  });
  testWidgets('Appearance preference toggles light and dark', (tester) async {
    final f = await QaFixture.create();
    await f.pump(
      tester,
      ProfileTabView(appUser: (await f.service.getUser(QaFixture.uid))!),
    );
    await tester.ensureVisible(find.text('App Appearance'));
    await tester.tap(find.text('App Appearance'));
    await tester.pumpAndSettle();
    expect(f.container.read(themeModeProvider), ThemeMode.dark);
    await tester.tap(find.text('App Appearance'));
    await tester.pumpAndSettle();
    expect(f.container.read(themeModeProvider), ThemeMode.light);
  });
  testWidgets('Gold user can select Egyptian Gold theme', (tester) async {
    final f = await QaFixture.create(gold: true);
    await f.pump(
      tester,
      ProfileTabView(appUser: (await f.service.getUser(QaFixture.uid))!),
    );
    await tester.ensureVisible(find.text('Premium Theme'));
    await tester.tap(find.text('Premium Theme'));
    await tester.pumpAndSettle();
    expect(f.container.read(appThemeProvider), AppTheme.egyptianGold);
  });
  testWidgets('Notification switch persists disabled preference', (
    tester,
  ) async {
    final f = await QaFixture.create();
    await f.pump(
      tester,
      ProfileTabView(appUser: (await f.service.getUser(QaFixture.uid))!),
    );
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(
      (await f.service.getUser(QaFixture.uid))!.notificationsEnabled,
      false,
    );
  });
  testWidgets('Household details editor saves name', (tester) async {
    final f = await QaFixture.create();
    await f.pump(
      tester,
      Scaffold(
        body: FamilyOverviewCard(household: f.household, memberCount: 1),
      ),
    );
    await tester.tap(find.text('Edit Details'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Renamed QA Family');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      (await f.db.doc('households/${f.householdId}').get()).data()!['name'],
      'Renamed QA Family',
    );
  });
  testWidgets('Invitation QR opens and displays the household code', (
    tester,
  ) async {
    final f = await QaFixture.create();
    await f.pump(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: InviteCodeCard(household: f.household),
        ),
      ),
    );
    await tester.tap(find.text('Show QR'));
    await tester.pumpAndSettle();
    expect(find.byType(QrDialog), findsOneWidget);
    expect(find.text('Code: ${f.household!.inviteCode}'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(QrDialog), findsNothing);
  });
  testWidgets(
    'Household owner refreshes an invite and invalidates the old code',
    (tester) async {
      final f = await QaFixture.create();
      final oldCode = f.household!.inviteCode;
      await f.pump(tester, const HomeScreen());
      await tester.tap(find.text('Household').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Refresh invite'));
      await tester.tap(find.text('Refresh invite'));
      await tester.pumpAndSettle();

      final stored = (await f.db.doc('households/${f.householdId}').get())
          .data()!;
      final newCode = stored['inviteCode'] as String;
      expect(newCode, isNot(oldCode));
      expect((await f.db.doc('inviteCodes/$oldCode').get()).exists, false);
      expect(
        (await f.db.doc('inviteCodes/$newCode').get()).data()!['householdId'],
        f.householdId,
      );
      await tester.ensureVisible(find.text('Show QR'));
      await tester.tap(find.text('Show QR'));
      await tester.pumpAndSettle();
      expect(find.text('Code: $newCode'), findsOneWidget);
    },
  );
  testWidgets(
    'A member who is not the household owner cannot refresh invites',
    (tester) async {
      final f = await QaFixture.create();
      await f.db.doc('households/${f.householdId}').update({
        'createdBy': 'other-owner',
      });
      await f.pump(tester, const HomeScreen());
      await tester.tap(find.text('Household').last);
      await tester.pumpAndSettle();
      expect(find.text('Refresh invite'), findsNothing);
    },
  );
  testWidgets(
    'Invite refresh disables duplicate calls and exposes failures for retry',
    (tester) async {
      final f = await QaFixture.create(
        serviceFactory: ControlledInviteService.new,
      );
      final service = f.service as ControlledInviteService;
      final oldCode = f.household!.inviteCode;
      await f.pump(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: InviteCodeCard(household: f.household),
          ),
        ),
      );
      await tester.tap(find.text('Refresh invite'));
      await tester.tap(find.text('Refresh invite'));
      await tester.pump();
      expect(service.refreshCalls, 1);
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Refreshing invite…'),
            )
            .onPressed,
        isNull,
      );
      service.releaseRefresh.complete();
      await tester.pumpAndSettle();
      expect(
        find.text('Could not refresh the invite. Please try again.'),
        findsOneWidget,
      );
      expect((await f.db.doc('inviteCodes/$oldCode').get()).exists, true);

      service.rejectRefresh = false;
      await tester.tap(find.text('Refresh invite'));
      await tester.pumpAndSettle();
      expect(service.refreshCalls, 2);
      expect(
        find.text('Could not refresh the invite. Please try again.'),
        findsNothing,
      );
      expect((await f.db.doc('inviteCodes/$oldCode').get()).exists, false);
    },
  );
  testWidgets('Create new list saves a named list from Options', (
    tester,
  ) async {
    final f = await QaFixture.create();
    await f.pump(
      tester,
      Scaffold(
        body: ListTabView(
          appUser: (await f.service.getUser(QaFixture.uid))!,
          household: f.household,
        ),
      ),
    );
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create New List'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Weekend');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(
      (await f.service.watchGroceryLists(f.householdId).first).map(
        (l) => l.name,
      ),
      contains('Weekend'),
    );
  });
  testWidgets('Gold users have the list export action', (tester) async {
    final f = await QaFixture.create(gold: true);
    await f.pump(
      tester,
      Scaffold(
        body: ListTabView(
          appUser: (await f.service.getUser(QaFixture.uid))!,
          household: f.household,
        ),
      ),
    );
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    expect(find.text('Export to WhatsApp'), findsOneWidget);
  });
  testWidgets('Non-Gold users do not have the export action', (tester) async {
    final f = await QaFixture.create();
    await f.pump(
      tester,
      Scaffold(
        body: ListTabView(
          appUser: (await f.service.getUser(QaFixture.uid))!,
          household: f.household,
        ),
      ),
    );
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    expect(find.text('Export to WhatsApp'), findsNothing);
  });
  testWidgets('Error screen retry invokes recovery action', (tester) async {
    final f = await QaFixture.create();
    var retried = false;
    await f.pump(
      tester,
      ErrorScreen(error: 'Local test failure', onRetry: () => retried = true),
    );
    await tester.tap(find.text('Try Again'));
    expect(retried, true);
  });
  testWidgets('QA-12 Whitespace-only shopping list names are rejected', (
    tester,
  ) async {
    final f = await QaFixture.create();
    await f.pump(
      tester,
      Scaffold(
        body: ListTabView(
          appUser: (await f.service.getUser(QaFixture.uid))!,
          household: f.household,
        ),
      ),
    );
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create New List'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '   ');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect((await f.service.watchGroceryLists(f.householdId).first).length, 1);
    expect(find.text('New Shopping List'), findsOneWidget);
    expect(find.text('Enter a list name'), findsOneWidget);
  });
  testWidgets('QA-13 Member without a display name renders safely', (
    tester,
  ) async {
    final f = await QaFixture.create();
    final user = (await f.service.getUser(
      QaFixture.uid,
    ))!.copyWith(displayName: '');
    await f.pump(tester, Scaffold(body: MemberTile(user: user, isMe: true)));
    expect(tester.takeException(), isNull);
    expect(find.text('?'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('User Info'));
    await tester.pumpAndSettle();
    expect(find.text('Email'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Profile member avatars handle blank display names', (
    tester,
  ) async {
    final f = await QaFixture.create();
    await f.db.doc('users/${QaFixture.uid}').update({'displayName': '  '});
    await f.pump(
      tester,
      ProfileTabView(appUser: (await f.service.getUser(QaFixture.uid))!),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('?'), findsOneWidget);
  });
  testWidgets('Failed list creation keeps the name and retry action', (
    tester,
  ) async {
    final f = await QaFixture.create(serviceFactory: FailingListService.new);
    await f.pump(
      tester,
      Scaffold(
        body: ListTabView(
          appUser: (await f.service.getUser(QaFixture.uid))!,
          household: f.household,
        ),
      ),
    );
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create New List'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Keep my list');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.text('New Shopping List'), findsOneWidget);
    expect(
      find.text('Could not create the list. Please try again.'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      'Keep my list',
    );
    expect((await f.service.watchGroceryLists(f.householdId).first).length, 1);
  });
  testWidgets('Family Gold member can export lists without banner ads', (
    tester,
  ) async {
    final f = await familyGoldFixture();
    await f.pump(
      tester,
      Scaffold(
        body: ListTabView(
          appUser: (await f.service.getUser(QaFixture.uid))!,
          household: f.household,
        ),
      ),
    );
    expect(find.byType(BannerAdWidget), findsNothing);
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    expect(find.text('Export to WhatsApp'), findsOneWidget);
  });
  testWidgets('Family Gold member can select the premium theme', (
    tester,
  ) async {
    final f = await familyGoldFixture();
    await f.pump(
      tester,
      ProfileTabView(appUser: (await f.service.getUser(QaFixture.uid))!),
    );
    expect(find.text('Upgrade to Na2slna Pro'), findsNothing);
    await tester.ensureVisible(find.text('Premium Theme'));
    await tester.tap(find.text('Premium Theme'));
    await tester.pumpAndSettle();
    expect(f.container.read(appThemeProvider), AppTheme.egyptianGold);
  });
  testWidgets('QA-14 Family Gold gives other household members photo access', (
    tester,
  ) async {
    final f = await QaFixture.create();
    await f.db.doc('users/gold-admin').set({
      'displayName': 'Gold Admin',
      'householdId': f.householdId,
      'role': 'familyAdmin',
      'isGold': true,
    });
    await f.db.doc('households/${f.householdId}').update({
      'createdBy': 'gold-admin',
    });
    await f.db.doc('users/${QaFixture.uid}').update({'role': 'familyMember'});
    await f.pump(tester, const Scaffold(body: AddItemDialog()));
    expect(find.text('Add Photo'), findsOneWidget);
  });
}
