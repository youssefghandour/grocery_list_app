import 'package:flutter/material.dart';

class EmptyListIllustration extends StatelessWidget {
  const EmptyListIllustration({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 64),
        child: Column(
          children: [
            Icon(Icons.shopping_basket_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('Your list is empty', style: TextStyle(color: Colors.grey, fontSize: 18)),
          ],
        ),
      ),
    );
  }
}
