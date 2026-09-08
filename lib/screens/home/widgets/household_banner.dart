import 'package:flutter/material.dart';
import '../../../models/household_model.dart';

class HouseholdBanner extends StatelessWidget {
  const HouseholdBanner({super.key, required this.household});
  final Household? household;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.group_outlined, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            household?.name ?? 'My Household',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const Spacer(),
          Icon(Icons.sync, size: 16, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
        ],
      ),
    );
  }
}
