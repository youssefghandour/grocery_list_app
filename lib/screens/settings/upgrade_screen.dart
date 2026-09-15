import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../../services/payment_service.dart';

class UpgradeScreen extends ConsumerStatefulWidget {
  const UpgradeScreen({super.key});

  @override
  ConsumerState<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends ConsumerState<UpgradeScreen> {
  List<ProductDetails> _products = [];
  bool _isLoading = true;
  bool _isBusy = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    if (kIsWeb) {
      setState(() {
        _isLoading = false;
      });
      return;
    }
    try {
      final products = await ref.read(paymentServiceProvider).fetchProducts();
      if (mounted) setState(() => _products = products);
    } catch (error) {
      if (mounted) {
        setState(
          () => _loadError = error is PaymentException
              ? error.message
              : 'Could not load plans. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _runPayment(
    Future<void> Function() action,
    String failure, {
    String? success,
  }) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await action();
      if (mounted && success != null) _showMessage(success);
    } catch (error) {
      if (mounted) {
        _showMessage(error is PaymentException ? error.message : failure);
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _buy(ProductDetails product) => _runPayment(
    () => ref.read(paymentServiceProvider).buyProduct(product),
    'Could not start your purchase. Please try again.',
  );

  void _buyWeb(String planType) => _runPayment(
    () =>
        ref.read(paymentServiceProvider).startPaymobCheckout(context, planType),
    'Could not open checkout. Please try again.',
  );

  void _restore() => _runPayment(
    () => ref.read(paymentServiceProvider).restorePurchases(),
    'Could not restore purchases. Please try again.',
    success: 'Restoring purchases... Please wait.',
  );

  @override
  Widget build(BuildContext context) {
    ref.listen(paymentMessageProvider, (_, message) {
      if (message != null) _showMessage(message);
    });
    final proProducts = _products.where((p) => p.id == PaymentService.proId);
    final goldProducts = _products.where((p) => p.id == PaymentService.goldId);
    final pro = proProducts.isEmpty ? null : proProducts.first;
    final gold = goldProducts.isEmpty ? null : goldProducts.first;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Na2slna Gold'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : AbsorbPointer(
              absorbing: _isBusy,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 24),
                    // Brand Header
                    Center(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFA000),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFFFFA000,
                                  ).withValues(alpha: 0.3),
                                  blurRadius: 15,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.star_rounded,
                              color: Colors.white,
                              size: 48,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Na2slna Gold',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 40),
                            child: Text(
                              'Pay once, enjoy premium features forever. No subscriptions.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (_isBusy) const LinearProgressIndicator(),
                    if (_loadError != null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(_loadError!, textAlign: TextAlign.center),
                      ),
                      TextButton(
                        onPressed: _loadProducts,
                        child: const Text('Retry'),
                      ),
                    ],

                    // Plan Buttons (Dynamic from Store)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          if (kIsWeb) ...[
                            Expanded(
                              child: _PlanButton(
                                title: 'Basic Pro',
                                price: '75.00 EGP',
                                subtitle: 'Remove all ads',
                                color: const Color(0xFF2E7D32),
                                onTap: () => _buyWeb('pro'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _PlanButton(
                                title: 'Family Gold',
                                price: '150.00 EGP',
                                subtitle: 'The full bundle',
                                color: const Color(0xFFFFA000),
                                onTap: () => _buyWeb('gold'),
                              ),
                            ),
                          ] else if (pro != null || gold != null) ...[
                            if (pro != null)
                              Expanded(
                                child: _PlanButton(
                                  title: 'Basic Pro',
                                  price: pro.price,
                                  subtitle: 'Remove all ads',
                                  color: const Color(0xFF2E7D32),
                                  onTap: () => _buy(pro),
                                ),
                              ),
                            if (pro != null && gold != null)
                              const SizedBox(width: 12),
                            if (gold != null)
                              Expanded(
                                child: _PlanButton(
                                  title: 'Family Gold',
                                  price: gold.price,
                                  subtitle: 'The full bundle',
                                  color: const Color(0xFFFFA000),
                                  onTap: () => _buy(gold),
                                ),
                              ),
                          ] else if (_loadError == null) ...[
                            const Expanded(
                              child: Center(
                                child: Text('No products found in store.'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Family Gold unlocks premium features for your entire household.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),

                    // Features List
                    const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Premium Features',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 24),
                          _FeatureItem(
                            icon: Icons.ad_units,
                            title: 'No Advertisements',
                            subtitle:
                                'Focus on your shopping without any distractions.',
                            isGoldOnly: false,
                          ),
                          _FeatureItem(
                            icon: Icons.photo_camera_outlined,
                            title: 'Item Photos',
                            subtitle:
                                'Attach photos to items so family buys exactly what you need.',
                            isGoldOnly: true,
                          ),
                          _FeatureItem(
                            icon: Icons.share_rounded,
                            title: 'WhatsApp Export',
                            subtitle:
                                'Format and send your list to anyone with one tap.',
                            isGoldOnly: true,
                          ),
                          _FeatureItem(
                            icon: Icons.groups_3_outlined,
                            title: 'Unlimited Members',
                            subtitle:
                                'Add as many family members as you want to your household.',
                            isGoldOnly: true,
                          ),
                          _FeatureItem(
                            icon: Icons.palette_outlined,
                            title: 'Exclusive Themes',
                            subtitle:
                                'Unlock the "Egyptian Gold" and "Midnight" premium designs.',
                            isGoldOnly: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
                    if (!kIsWeb)
                      TextButton(
                        onPressed: _restore,
                        child: const Text(
                          'Restore Purchases',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }
}

class _PlanButton extends StatelessWidget {
  const _PlanButton({
    required this.title,
    required this.price,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
  final String title;
  final String price;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              price,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.isGoldOnly,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isGoldOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: theme.colorScheme.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    if (isGoldOnly) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFA000).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: const Color(
                              0xFFFFA000,
                            ).withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Text(
                          'GOLD',
                          style: TextStyle(
                            color: Color(0xFFFFA000),
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
