import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/household/create_household_screen.dart';
import 'screens/household/join_household_screen.dart';
// import 'screens/home/purchase_later_screen.dart';

import 'package:google_fonts/google_fonts.dart';
import 'services/deep_link_service.dart';

class AppColors {
  // Brand Market Green Palette
  static const primary = Color(0xFF2E7D32);
  static const primaryContainer = Color(0xFFC8E6C9);
  static const onPrimary = Colors.white;

  // Backgrounds & Surfaces (Light)
  static const surface = Color(0xFFF7FBF0);
  static const surfaceContainer = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFF1F5EB);

  // Dark Mode Surfaces
  static const darkSurface = Color(0xFF121411);
  static const darkCardSurface = Color(0xFF1E211D);
  static const darkFloatingBar = Color(0xFF1B2418);

  // Accents
  static const goldAccent = Color(0xFFFFA000);
  static const outlineVariant = Color(0xFFE0E5DA);
  static const textPrimary = Color(0xFF1B1C18);
  static const textSecondary = Color(0xFF72796F);
}

class Na2slnaApp extends ConsumerStatefulWidget {
  const Na2slnaApp({super.key});

  @override
  ConsumerState<Na2slnaApp> createState() => _Na2slnaAppState();
}

class _Na2slnaAppState extends ConsumerState<Na2slnaApp> {
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    // Delay initialization until the app is fully built
    Future.microtask(() {
      if (mounted) {
        ref.read(deepLinkServiceProvider).initialize(_scaffoldMessengerKey);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = GoogleFonts.plusJakartaSansTextTheme();

    return MaterialApp(
      title: 'Na2slna',
      scaffoldMessengerKey: _scaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        textTheme: textTheme,
        colorScheme: ColorScheme.light(
          primary: AppColors.primary,
          onPrimary: Colors.white,
          primaryContainer: AppColors.primaryContainer,
          onPrimaryContainer: const Color(0xFF1B5E20),
          secondary: AppColors.goldAccent,
          onSecondary: Colors.white,
          secondaryContainer: AppColors.goldAccent.withValues(alpha: 0.1),
          onSecondaryContainer: AppColors.goldAccent,
          tertiary: const Color(0xFF923357),
          surface: AppColors.surface,
          onSurface: AppColors.textPrimary,
          surfaceContainerHighest: AppColors.outlineVariant,
          onSurfaceVariant: AppColors.textSecondary,
          outline: AppColors.textSecondary,
          outlineVariant: AppColors.outlineVariant,
          error: const Color(0xFFBA1A1A),
        ),
        scaffoldBackgroundColor: AppColors.surface,
        cardTheme: CardThemeData(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: Colors.white,
        ),
        navigationBarTheme: NavigationBarThemeData(
          indicatorColor: AppColors.goldAccent.withValues(alpha: 0.15),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: Color(0xFF785900));
            }
            return const IconThemeData(color: AppColors.textSecondary);
          }),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        bottomAppBarTheme: const BottomAppBarThemeData(
          color: Color(0xFF1B5E20),
          elevation: 3,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            shape: const StadiumBorder(),
          ),
        ),
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        textTheme: GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4CAF50), // Vibrant Green for Price/Titles
          onPrimary: Colors.white,
          primaryContainer: Color(0xFF2E7D32), // Deeper Green for FAB
          onPrimaryContainer: Colors.white,
          secondary: AppColors.goldAccent, // Egyptian Gold #FFA000
          onSecondary: Colors.black,
          secondaryContainer: Color(0xFF3F2E00),
          onSecondaryContainer: AppColors.goldAccent,
          surface: Color(0xFF121411), // Obsidian background
          onSurface: Color(0xFFE2E3DD),
          surfaceContainerLow: Color(0xFF1B211A), // Card background (greenish-grey)
          surfaceContainer: Color(0xFF151914),    // Item background (darker)
          surfaceContainerHigh: Color(0xFF252923),
          outline: Color(0xFF44483F),
          outlineVariant: Color(0xFF2C312A),
        ),
        scaffoldBackgroundColor: const Color(0xFF121411),
        cardTheme: CardThemeData(
          elevation: 0,
          color: const Color(0xFF1B211A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: const Color(0xFF2E7D32),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF121411),
          elevation: 0,
          indicatorColor: const Color(0xFF4CAF50).withValues(alpha: 0.1),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: Color(0xFF4CAF50));
            }
            return const IconThemeData(color: Color(0xFF8D9286));
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const TextStyle(color: Color(0xFF4CAF50), fontSize: 12, fontWeight: FontWeight.bold);
            }
            return const TextStyle(color: Color(0xFF8D9286), fontSize: 12);
          }),
        ),
      ),
      themeMode: ref.watch(themeModeProvider),
      routes: {
        '/': (_) => const _AuthGate(),
        '/login': (_) => const LoginScreen(),
        '/register': (_) => const RegisterScreen(),
        '/home': (_) => const HomeScreen(),
        // '/purchase-later': (_) => const PurchaseLaterScreen(),
        '/create-household': (_) => const CreateHouseholdScreen(),
        '/join-household': (_) => const JoinHouseholdScreen(),
      },
      initialRoute: '/',
    );
  }
}

/// Routes authenticated users to HomeScreen, others to LoginScreen.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      loading: () => Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                const CircularProgressIndicator(),
                const SizedBox(height: 24),
                Text(
                  'Checking for your lists...',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Text(
                        "Taking too long?",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.pushNamed(context, '/login'),
                        icon: const Icon(Icons.add_task),
                        label: const Text('Add to the lists'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      error: (error, _) => Scaffold(
        body: Center(child: Text('Auth error: $error')),
      ),
      data: (user) {
        if (user == null) return const LoginScreen();
        return const HomeScreen();
      },
    );
  }
}
