import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/carrefour_api_service.dart';

Future<void> showCarrefourPrices({
  required BuildContext context,
  required String itemName,
  required String unit,
  required Future<void> Function(CarrefourProduct product) onSelect,
}) {
  final service = CarrefourApiService();
  final results = service.searchMatches(itemName);

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Carrefour prices',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Search results for "$itemName" · Tap a product to use and remember it for this household.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<CarrefourProduct>>(
                  future: results,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return _Message(
                        icon: Icons.cloud_off_outlined,
                        text:
                            '${snapshot.error}\n\nThe Carrefour price service is temporarily unavailable.',
                      );
                    }

                    final products = snapshot.data ?? const [];
                    if (products.isEmpty) {
                      return const _Message(
                        icon: Icons.search_off,
                        text:
                            'No matching Carrefour products found. The catalog may need a refresh, or try a more specific search.',
                      );
                    }

                    return ListView.separated(
                      itemCount: products.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final product = products[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              if ((product.brand ?? '').isNotEmpty)
                                product.brand!,
                              if (product.lastSeen != null)
                                'Updated ${_formatDate(product.lastSeen!)}',
                            ].join(' · '),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    product.price == null
                                        ? 'Price unavailable'
                                        : '${product.price!.toStringAsFixed(2)} EGP',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  if (product.oldPrice != null &&
                                      product.price != null &&
                                      product.oldPrice! > product.price!)
                                    Text(
                                      '${product.oldPrice!.toStringAsFixed(2)} EGP',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            decoration:
                                                TextDecoration.lineThrough,
                                          ),
                                    ),
                                  if (service.priceForUnit(product, unit) !=
                                      null)
                                    Text(
                                      'List price: ${service.priceForUnit(product, unit)!.toStringAsFixed(2)} EGP/$unit',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelSmall,
                                    ),
                                ],
                              ),
                              IconButton(
                                tooltip: 'Open Carrefour product page',
                                visualDensity: VisualDensity.compact,
                                onPressed: (product.url ?? '').isEmpty
                                    ? null
                                    : () => launchUrl(
                                        Uri.parse(product.url!),
                                        mode: LaunchMode.externalApplication,
                                      ),
                                icon: const Icon(Icons.open_in_new, size: 18),
                              ),
                            ],
                          ),
                          onTap: product.price == null
                              ? null
                              : () async {
                                  try {
                                    await onSelect(product);
                                    if (context.mounted) {
                                      Navigator.of(context).pop();
                                      ScaffoldMessenger.of(context)
                                        ..hideCurrentSnackBar()
                                        ..showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Saved this Carrefour product for "$itemName".',
                                            ),
                                          ),
                                        );
                                    }
                                  } catch (error) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Could not save this product: $error',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ).whenComplete(service.close);
}

String _formatDate(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  if (date == null) return value;
  return '${date.day}/${date.month}/${date.year}';
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
