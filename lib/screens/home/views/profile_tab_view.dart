import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../../../models/user_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/household_provider.dart';
import '../../../providers/home_provider.dart';
import '../../../providers/settings_provider.dart';
import '../widgets/home_top_header.dart';
import '../widgets/profile_widgets.dart';

class ProfileTabView extends ConsumerWidget {
  const ProfileTabView({super.key, required this.appUser});
  final AppUser appUser;

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url)) {
      debugPrint('Could not launch $url');
    }
  }

  void _showEditNameDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: appUser.displayName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Display Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter new name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await ref.read(firestoreServiceProvider).updateDisplayName(appUser.uid, controller.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = ref.watch(householdProvider).valueOrNull;
    final members = ref.watch(householdMembersProvider).valueOrNull ?? [];
    final themeMode = ref.watch(themeModeProvider);
    
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? theme.colorScheme.surface : const Color(0xFFF9FBF6),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HomeTopHeader(user: appUser),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Profile & Settings',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 18, // Reduced to prevent overflow
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Manage family shared basket & options',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified_user, color: Colors.green, size: 12),
                          SizedBox(width: 4),
                          Text('Connected', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 1. User Profile Card
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  boxShadow: [
                    if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundImage: appUser.imageUrl != null ? NetworkImage(appUser.imageUrl!) : null,
                          child: appUser.imageUrl == null ? const Icon(Icons.person, size: 32) : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(appUser.displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  appUser.role.name == 'familyAdmin' ? 'Household Organizer' : 'Family Member',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => _showEditNameDialog(context, ref), 
                          icon: const Icon(Icons.edit_outlined, size: 20)
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow(context, Icons.email_outlined, appUser.email),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 2. Household Card
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.home_outlined, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(household?.name ?? 'My Household', style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text('${members.length} Active Members Syncing', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () => ref.read(navigationIndexProvider.notifier).state = 1, 
                          child: const Text('Manage >')
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SizedBox(
                          width: 80,
                          child: _buildMembersStack(context, members),
                        ),
                        InkWell(
                          onTap: () {
                            if (household?.inviteCode != null) {
                              Clipboard.setData(ClipboardData(text: household!.inviteCode));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Invite code copied to clipboard')),
                              );
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Text('Code: ', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                                Text(household?.inviteCode ?? '------', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1)),
                                const SizedBox(width: 8),
                                const Icon(Icons.copy, size: 14),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const ProfileSectionHeader(title: 'Preferences & App Settings'),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    ProfileListTile(
                      icon: Icons.dark_mode_outlined,
                      title: 'App Appearance',
                      subtitle: 'Theme & visual display',
                      trailing: Text(themeMode == ThemeMode.dark ? 'Dark Mode' : 'Light Mode', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                      onTap: () {
                        ref.read(themeModeProvider.notifier).state = 
                          themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
                      },
                    ),
                    const ProfileListTile(
                      icon: Icons.translate,
                      title: 'Language',
                      subtitle: 'Current display tongue',
                      trailing: Text('English / العربية', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    ProfileListTile(
                      icon: Icons.notifications_none_outlined,
                      title: 'List Notifications',
                      subtitle: 'When family adds items or checks off',
                      trailing: Switch(
                        value: appUser.notificationsEnabled, 
                        onChanged: (v) => ref.read(firestoreServiceProvider).updateNotificationPreference(appUser.uid, v),
                        activeThumbColor: Colors.green,
                      ),
                    ),
                    const ProfileListTile(
                      icon: Icons.monetization_on_outlined,
                      title: 'Market Currency',
                      subtitle: 'Supermarket pricing comparison',
                      trailing: Text('EGP (ج.م) >', style: TextStyle(color: Colors.grey)),
                    ),
                    ProfileListTile(
                      icon: Icons.group_add_outlined,
                      title: 'Household Management',
                      subtitle: 'Roles, permissions & QR invites',
                      showDivider: false,
                      onTap: () => ref.read(navigationIndexProvider.notifier).state = 1,
                    ),
                  ],
                ),
              ),

              const ProfileSectionHeader(title: 'Support & About'),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    ProfileListTile(
                      icon: Icons.help_outline,
                      title: 'Help Center & FAQ',
                      trailing: const Icon(Icons.open_in_new, size: 16, color: Colors.grey),
                      onTap: () => _launchUrl('https://na2slna.web.app/help'),
                    ),
                    ProfileListTile(
                      icon: Icons.share_outlined,
                      title: 'Share Na2slna with Friends',
                      onTap: () {
                        Share.share(
                          'Na2slna - Shared Grocery Lists for the Family! 🛒\n\nInstantly sync items, track prices, and stay organized. Join the beta now!\n\nDownload: https://na2slna.web.app',
                          subject: 'Na2slna: Shared Grocery List',
                        );
                      },
                    ),
                    ProfileListTile(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacy Policy & Terms',
                      showDivider: false,
                      onTap: () => _launchUrl('https://na2slna.web.app/privacy'),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),
              const Center(
                child: Text(
                  '• شرف اللي ناقص.. والكل يعرف •',
                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'Na2slna (Beta) v1.1.0 (Build 204)',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5), fontSize: 10),
                ),
              ),

              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton(
                  onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMembersStack(BuildContext context, List<AppUser> members) {
    const double avatarRadius = 14;
    const double overlapOffset = 18;
    const int maxAvatars = 3;

    final displayMembers = members.take(maxAvatars).toList();
    final remainingCount = members.length - maxAvatars;

    return SizedBox(
      height: avatarRadius * 2,
      child: Stack(
        children: [
          for (int i = 0; i < displayMembers.length; i++)
            Positioned(
              left: i * overlapOffset.toDouble(),
              child: CircleAvatar(
                radius: avatarRadius,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                backgroundImage: displayMembers[i].imageUrl != null
                    ? NetworkImage(displayMembers[i].imageUrl!)
                    : null,
                child: displayMembers[i].imageUrl == null
                    ? Text(
                        displayMembers[i].displayName[0].toUpperCase(),
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      )
                    : null,
              ),
            ),
          if (remainingCount > 0)
            Positioned(
              left: maxAvatars * overlapOffset.toDouble(),
              child: CircleAvatar(
                radius: avatarRadius,
                backgroundColor: Colors.grey,
                child: Text(
                  '+$remainingCount',
                  style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant)),

      ],
    );
  }
}
