// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:url_launcher/url_launcher.dart';
// import '../../models/product_cache_model.dart';
// import '../../providers/grocery_list_provider.dart';
//
// class PurchaseLaterScreen extends ConsumerWidget {
//   const PurchaseLaterScreen({super.key});
//
//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final matchesAsync = ref.watch(purchaseLaterProvider);
//
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Deals & Offers'),
//         centerTitle: true,
//       ),
//       body: matchesAsync.when(
//         data: (matches) {
//           if (matches.isEmpty) {
//             return Center(
//               child: Column(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   Icon(
//                     Icons.local_offer_outlined,
//                     size: 64,
//                     color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
//                   ),
//                   const SizedBox(height: 16),
//                   const Text(
//                     'No deals found yet.\nAdd items to your list to see offers!',
//                     textAlign: TextAlign.center,
//                   ),
//                 ],
//               ),
//             );
//           }
//
//           return ListView.builder(
//             itemCount: matches.length,
//             padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
//             itemBuilder: (context, index) {
//               final match = matches[index];
//               return _ProductMatchCard(match: match);
//             },
//           );
//         },
//         loading: () => const Center(child: CircularProgressIndicator()),
//         error: (e, _) => Center(child: Text('Error: $e')),
//       ),
//     );
//   }
// }
//
// class _ProductMatchCard extends StatelessWidget {
//   const _ProductMatchCard({required this.match});
//
//   final ProductMatch match;
//
//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//
//     return Card(
//       margin: const EdgeInsets.only(bottom: 16),
//       clipBehavior: Clip.antiAlias,
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.stretch,
//         children: [
//           Row(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               if (match.imageUrl.isNotEmpty)
//                 Padding(
//                   padding: const EdgeInsets.all(12.0),
//                   child: ClipRRect(
//                     borderRadius: BorderRadius.circular(12),
//                     child: Image.network(
//                       match.imageUrl,
//                       width: 80,
//                       height: 80,
//                       fit: BoxFit.cover,
//                     ),
//                   ),
//                 ),
//               Expanded(
//                 child: Padding(
//                   padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text(
//                         match.displayName,
//                         style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
//                         maxLines: 2,
//                         overflow: TextOverflow.ellipsis,
//                       ),
//                       if (match.brand.isNotEmpty)
//                         Text(
//                           match.brand,
//                           style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
//                         ),
//                     ],
//                   ),
//                 ),
//               ),
//             ],
//           ),
//           const Divider(height: 1, indent: 16, endIndent: 16),
//           ...match.links.where((l) => l.isLowestPrice || l.isSale).map((link) => Column(
//                 children: [
//                   ListTile(
//                     dense: true,
//                     contentPadding: const EdgeInsets.symmetric(horizontal: 16),
//                     leading: link.brochureUrl != null
//                         ? ClipRRect(
//                             borderRadius: BorderRadius.circular(4),
//                             child: Image.network(link.brochureUrl!, width: 32, height: 32, fit: BoxFit.cover),
//                           )
//                         : Icon(Icons.store_outlined, color: theme.colorScheme.primary),
//                     title: Text(link.storeName, style: const TextStyle(fontWeight: FontWeight.w600)),
//                     subtitle: link.isSale
//                         ? Text('🔥 FLASH SALE',
//                             style: TextStyle(color: theme.colorScheme.error, fontSize: 10, fontWeight: FontWeight.bold))
//                         : null,
//                     trailing: Row(
//                       mainAxisSize: MainAxisSize.min,
//                       children: [
//                         if (link.isLowestPrice)
//                           Container(
//                             padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
//                             decoration: BoxDecoration(
//                               color: theme.colorScheme.secondary,
//                               borderRadius: BorderRadius.circular(4),
//                             ),
//                             child: Text(
//                               'BEST',
//                               style: TextStyle(
//                                 color: theme.colorScheme.onSecondary,
//                                 fontSize: 9,
//                                 fontWeight: FontWeight.bold,
//                               ),
//                             ),
//                           ),
//                         const SizedBox(width: 8),
//                         Text(
//                           '${link.price.toStringAsFixed(2)} EGP',
//                           style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
//                         ),
//                         const SizedBox(width: 4),
//                         IconButton(
//                           icon: const Icon(Icons.open_in_new, size: 18),
//                           onPressed: () => launchUrl(Uri.parse(link.url), mode: LaunchMode.externalApplication),
//                           visualDensity: VisualDensity.compact,
//                         ),
//                       ],
//                     ),
//                   ),
//                 ],
//               )),
//           const SizedBox(height: 8),
//         ],
//       ),
//     );
//   }
// }
