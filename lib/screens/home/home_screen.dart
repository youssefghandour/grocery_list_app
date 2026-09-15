import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../providers/home_provider.dart';
import '../../providers/household_provider.dart';
import '../../widgets/error_screen.dart';
import '../../widgets/onboarding_screen.dart';
import '../../services/notification_service.dart';
import 'views/list_tab_view.dart';
import 'views/household_tab_view.dart';
import 'views/profile_tab_view.dart';
import 'widgets/floating_budget_summary.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appUserAsync = ref.watch(appUserProvider);
    final householdAsync = ref.watch(householdProvider);
    final navigationIndex = ref.watch(navigationIndexProvider);

    return appUserAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => ErrorScreen(error: error.toString(), onRetry: () => ref.invalidate(appUserProvider)),
      data: (appUser) {
        if (appUser == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

        if (!appUser.hasHousehold) return OnboardingScreen(displayName: appUser.displayName);

        // Sync FCM token if it hasn't been set yet
        if (appUser.fcmToken == null) {
          NotificationService.instance.syncToken(appUser.uid, ref.read(firestoreServiceProvider));
        }

        return householdAsync.when(
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, _) => ErrorScreen(error: error.toString(), onRetry: () => ref.invalidate(householdProvider)),
          data: (household) {
            return Scaffold(
              body: IndexedStack(
                index: navigationIndex,
                children: [
                  ListTabView(appUser: appUser, household: household),
                  HouseholdTabView(appUser: appUser, household: household),
                  ProfileTabView(appUser: appUser),
                ],
              ),
              bottomNavigationBar: NavigationBar(
                elevation: 0,
                backgroundColor: Theme.of(context).colorScheme.surface,
                indicatorColor: Colors.green.withValues(alpha: 0.2),
                selectedIndex: navigationIndex,
                onDestinationSelected: (index) => ref.read(navigationIndexProvider.notifier).setIndex(index),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.list_alt_outlined),
                    selectedIcon: Icon(Icons.list_alt, color: Colors.green),
                    label: 'My Lists',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.people_outline),
                    selectedIcon: Icon(Icons.people, color: Colors.green),
                    label: 'Household',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person, color: Colors.green),
                    label: 'Profile',
                  ),
                ],
              ),
              floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
              floatingActionButton: navigationIndex == 0 ? const FloatingBudgetSummary() : null,
            );
          },
        );
      },
    );
  }
}
