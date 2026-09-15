import 'package:flutter/material.dart';
import '../../../models/user_model.dart';

class HomeTopHeader extends StatelessWidget {
  const HomeTopHeader({super.key, required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Image.asset("assets/na2slna.png", width: 35),
              if (user.isGold)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFA000),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('GOLD', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                  ),
                )
              else if (user.isPro)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('PRO', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
          CircleAvatar(
            radius: 18,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.2),
            backgroundImage: user.imageUrl != null ? NetworkImage(user.imageUrl!) : null,
            child: user.imageUrl == null
                ? Icon(Icons.person, color: Theme.of(context).colorScheme.primary, size: 20)
                : null,
          ),
        ],
      ),
    );
  }
}
