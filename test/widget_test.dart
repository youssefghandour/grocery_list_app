import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:na2slna/screens/auth/login_screen.dart';
import 'package:na2slna/screens/auth/register_screen.dart';
import 'package:na2slna/screens/household/create_household_screen.dart';
import 'package:na2slna/screens/household/join_household_screen.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: screen,
          routes: {'/register': (_) => const RegisterScreen()},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Login displays email, password, Google and account creation', (
    tester,
  ) async {
    await pump(tester, const LoginScreen());
    expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);
  });
  testWidgets('Empty login validates without contacting Firebase', (
    tester,
  ) async {
    await pump(tester, const LoginScreen());
    await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Password must be at least 6 characters'), findsOneWidget);
  });
  testWidgets('Password visibility toggles', (tester) async {
    await pump(tester, const LoginScreen());
    final password = find.byType(TextField).at(1);
    expect(tester.widget<TextField>(password).obscureText, true);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(tester.widget<TextField>(password).obscureText, false);
  });
  testWidgets('Create account navigation opens registration', (tester) async {
    await pump(tester, const LoginScreen());
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);
  });
  testWidgets('Registration validates required fields', (tester) async {
    await pump(tester, const RegisterScreen());
    await tester.tap(find.widgetWithText(FilledButton, 'Create Account'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your name'), findsOneWidget);
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Password must be at least 6 characters'), findsOneWidget);
  });
  testWidgets('Create household rejects a blank name', (tester) async {
    await pump(tester, const CreateHouseholdScreen());
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('Enter a household name'), findsOneWidget);
  });
  testWidgets('Join household validates invite length', (tester) async {
    await pump(tester, const JoinHouseholdScreen());
    await tester.enterText(find.byType(TextFormField), 'ABC');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid 6-character code'), findsOneWidget);
  });
  testWidgets('Invite input strips symbols and caps length at six', (
    tester,
  ) async {
    await pump(tester, const JoinHouseholdScreen());
    await tester.enterText(find.byType(TextFormField), 'a!b@c#123456');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'abc123',
    );
  });
}
