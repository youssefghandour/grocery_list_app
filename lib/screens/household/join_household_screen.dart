import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/household_provider.dart';
import '../../widgets/barcode_scanner_dialog.dart';

class JoinHouseholdScreen extends ConsumerStatefulWidget {
  const JoinHouseholdScreen({super.key});

  @override
  ConsumerState<JoinHouseholdScreen> createState() =>
      _JoinHouseholdScreenState();
}

class _JoinHouseholdScreenState extends ConsumerState<JoinHouseholdScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final String? result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const BarcodeScannerDialog()),
    );

    if (result == null) return;

    String? extractedCode;

    // Check if scanned value is directly the 6-char code
    if (result.trim().length == 6) {
      extractedCode = result.trim();
    } else {
      // Try to parse as a URL and extract the 'code' parameter
      try {
        final uri = Uri.parse(result);
        extractedCode = uri.queryParameters['code'];
      } catch (e) {
        debugPrint('QR_SCAN: Failed to parse scanned result: $e');
      }
    }

    if (extractedCode != null && extractedCode.length == 6) {
      _codeController.text = extractedCode.toUpperCase();
      _join();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid QR code. Please scan a valid household invite.')),
        );
      }
    }
  }

  Future<void> _join() async {
    if (!_formKey.currentState!.validate()) return;

    await ref
        .read(householdControllerProvider.notifier)
        .joinHousehold(_codeController.text.trim());

    if (!mounted) return;

    final error = ref.read(householdControllerProvider).error;
    if (error == null) {
      // Success - pop back to HomeScreen
      Navigator.of(context).pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(householdControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Join Household')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Enter the 6-character invite code shared by your Family Admin.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _codeController,
                  decoration: const InputDecoration(
                    labelText: 'Invite code',
                    hintText: 'ABC123',
                    prefixIcon: Icon(Icons.key_outlined),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                    LengthLimitingTextInputFormatter(6),
                  ],
                  validator: (value) {
                    if (value == null || value.trim().length != 6) {
                      return 'Enter a valid 6-character code';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: isLoading ? null : _join,
                  icon: const Icon(Icons.group_add_outlined),
                  label: isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Join Household'),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text('OR', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: isLoading ? null : _scanQr,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan Invite QR'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
