import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/product_cache_model.dart';
import '../../providers/grocery_list_provider.dart';

class PurchaseLaterScreen extends ConsumerWidget {
  const PurchaseLaterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matchesAsync = ref.watch(purchaseLaterProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase Later & Deals'),
      ),
      body: matchesAsync.when(
        data: (matches) {
          if (matches.isEmpty) {
            return const Center(
              child: Text('No product matches found yet.\nAdd items to your list to see deals!'),
            );
          }

          return ListView.builder(
            itemCount: matches.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final match = matches[index];
              return _ProductMatchCard(match: match);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _ProductMatchCard extends StatelessWidget {
  const _ProductMatchCard({required this.match});

  final ProductMatch match;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (match.imageUrl.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      match.imageUrl,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        match.displayName,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (match.brand.isNotEmpty)
                        Text(
                          match.brand,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Last searched: ${match.lastUpdated.day}/${match.lastUpdated.month}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 1),
          ...match.links.where((l) => l.isLowestPrice || l.isSale).map((link) => Column(
                children: [
                  ListTile(
                    dense: true,
                    leading: link.brochureUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.network(link.brochureUrl!, width: 40, height: 40, fit: BoxFit.cover),
                          )
                        : const Icon(Icons.store_outlined),
                    title: Text(link.storeName),
                    subtitle: link.isSale
                        ? const Text('🔥 FLASH SALE',
                            style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold))
                        : (link.dateFound != null ? Text('Found: ${link.dateFound!.split('T')[0]}', style: const TextStyle(fontSize: 10)) : null),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (link.isLowestPrice)
                          const Chip(
                            label: Text('Lowest', style: TextStyle(fontSize: 10)),
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            backgroundColor: Colors.green,
                            labelStyle: TextStyle(color: Colors.white),
                          ),
                        const SizedBox(width: 8),
                        Text(
                          'EGP ${link.price.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.open_in_new, size: 18),
                          onPressed: () => launchUrl(Uri.parse(link.url)),
                        ),
                      ],
                    ),
                  ),
                ],
              )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
