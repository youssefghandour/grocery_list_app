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
          Image.asset("assets/na2slna.png", width: 35),
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
