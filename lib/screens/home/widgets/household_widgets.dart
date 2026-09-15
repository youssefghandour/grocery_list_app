import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../models/household_model.dart';
import '../../../models/user_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/household_provider.dart';
import '../../../widgets/qr_dialog.dart';

class FamilyOverviewCard extends ConsumerWidget {
  const FamilyOverviewCard({
    super.key,
    required this.household,
    required this.memberCount,
  });
  final Household? household;
  final int memberCount;

  void _showEditHouseholdDialog(BuildContext context, WidgetRef ref) {
    if (household == null) return;

    final controller = TextEditingController(text: household!.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Household Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'Enter new name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                await ref
                    .read(firestoreServiceProvider)
                    .updateHouseholdName(household!.id, controller.text.trim());
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
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.home_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      household?.name ?? 'My Family',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$memberCount Active Members',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _showEditHouseholdDialog(context, ref),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Edit Details'),
            ),
          ),
        ],
      ),
    );
  }
}

class InviteCodeCard extends ConsumerStatefulWidget {
  const InviteCodeCard({super.key, required this.household});
  final Household? household;

  @override
  ConsumerState<InviteCodeCard> createState() => _InviteCodeCardState();
}

class _InviteCodeCardState extends ConsumerState<InviteCodeCard> {
  bool _isRefreshing = false;
  String? _refreshError;

  Household? get household => widget.household;

  Future<void> _refreshInvite() async {
    final currentHousehold = household;
    final user = ref.read(appUserProvider).value;
    if (_isRefreshing ||
        currentHousehold == null ||
        user?.uid != currentHousehold.createdBy ||
        user?.householdId != currentHousehold.id) {
      return;
    }

    setState(() {
      _isRefreshing = true;
      _refreshError = null;
    });
    try {
      await ref
          .read(firestoreServiceProvider)
          .refreshHouseholdInvite(currentHousehold.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invite refreshed. The previous code no longer works.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _refreshError = 'Could not refresh the invite. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  void _shareCode(BuildContext context) {
    if (household?.inviteCode != null) {
      final String code = household!.inviteCode;
      final String link = 'https://na2slna.web.app/join?code=$code';

      SharePlus.instance.share(
        ShareParams(
          text:
              'Join my household on Na2slna! Click the link to join: $link \n\nOr use code: $code',
        ),
      );
    }
  }

  void _showQr(BuildContext context) {
    if (household?.inviteCode != null) {
      final String code = household!.inviteCode;
      final String link = 'na2slna://join?code=$code';

      showDialog(
        context: context,
        builder: (context) =>
            QrDialog(data: link, title: 'Scan to Join Household'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(appUserProvider).value;
    final canRefresh =
        household != null &&
        user != null &&
        user.uid == household!.createdBy &&
        user.householdId == household!.id;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Household Invite Code',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.history, color: Colors.white, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'Valid 48h',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '#',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    household?.inviteCode.replaceAllMapped(
                          RegExp(r".{3}"),
                          (match) => "${match.group(0)} ",
                        ) ??
                        "",
                    style: const TextStyle(
                      color: Color(0xFFCBFFC2),
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.copy_all_rounded,
                    color: Colors.white70,
                    size: 28,
                  ),
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: household?.inviteCode ?? ''),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Invite code copied to clipboard'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: InviteActionButton(
                  icon: Icons.qr_code_2_rounded,
                  label: 'Show QR',
                  onTap: () => _showQr(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InviteActionButton(
                  icon: Icons.share_rounded,
                  label: 'Share Invite',
                  onTap: () => _shareCode(context),
                ),
              ),
            ],
          ),
          if (canRefresh) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _isRefreshing ? null : _refreshInvite,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white70,
              ),
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.refresh, size: 20),
              label: Text(
                _isRefreshing ? 'Refreshing invite…' : 'Refresh invite',
              ),
            ),
            const Text(
              'Creates a new code and expires the previous one.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            if (_refreshError != null) ...[
              const SizedBox(height: 8),
              Text(
                _refreshError!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFFFE0B2)),
              ),
            ],
          ],
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Share this code or let family members scan the QR code to instantly join your household.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class InviteActionButton extends StatelessWidget {
  const InviteActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MembersHeader extends StatelessWidget {
  const MembersHeader({
    super.key,
    required this.count,
    this.isUnlimited = false,
  });
  final int count;
  final bool isUnlimited;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Members',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            isUnlimited ? '$count Members' : '$count/5 Limit',
            style: theme.textTheme.labelSmall,
          ),
        ),
      ],
    );
  }
}

class MemberTile extends ConsumerWidget {
  const MemberTile({super.key, required this.user, required this.isMe});
  final AppUser user;
  final bool isMe;

  String get _initial => user.displayName.trim().isEmpty
      ? '?'
      : user.displayName.trim().characters.first.toUpperCase();

  void _showUserInfo(BuildContext context, AppUser user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            CircleAvatar(
              radius: 40,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.3),
              backgroundImage: user.imageUrl != null
                  ? NetworkImage(user.imageUrl!)
                  : null,
              child: user.imageUrl == null
                  ? Text(_initial, style: const TextStyle(fontSize: 32))
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              user.displayName,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              user.role.name == 'familyAdmin'
                  ? 'Household Organizer'
                  : 'Family Member',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.email_outlined),
              title: const Text('Email'),
              subtitle: Text(user.email),
              contentPadding: EdgeInsets.zero,
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Joined'),
              subtitle: Text(
                '${user.createdAt.day}/${user.createdAt.month}/${user.createdAt.year}',
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currentUser = ref.watch(appUserProvider).value;
    final isAdmin = currentUser?.role.name == 'familyAdmin';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: theme.colorScheme.primaryContainer.withValues(
          alpha: 0.3,
        ),
        backgroundImage: user.imageUrl != null
            ? NetworkImage(user.imageUrl!)
            : null,
        child: user.imageUrl == null
            ? Text(_initial, style: TextStyle(color: theme.colorScheme.primary))
            : null,
      ),
      title: Row(
        children: [
          Text(
            user.displayName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (isMe)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'You',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      subtitle: Text(
        user.role.name.substring(0, 1).toUpperCase() +
            user.role.name.substring(1),
        style: theme.textTheme.bodySmall,
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 20),
        onSelected: (value) async {
          if (value == 'info') {
            _showUserInfo(context, user);
          } else if (value == 'remove' && !isMe) {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Remove Member?'),
                content: Text(
                  'Are you sure you want to remove ${user.displayName} from the household?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(
                      'Remove',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              await ref
                  .read(householdControllerProvider.notifier)
                  .removeMember(user.uid);
            }
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'info',
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18),
                SizedBox(width: 12),
                Text('User Info'),
              ],
            ),
          ),
          if (isAdmin && !isMe)
            PopupMenuItem(
              value: 'remove',
              child: Row(
                children: [
                  Icon(
                    Icons.person_remove_outlined,
                    size: 18,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Remove Member',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
