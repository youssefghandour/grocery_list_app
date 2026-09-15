import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/grocery_list_provider.dart';
// import 'barcode_scanner_dialog.dart';

class QuickAddBar extends ConsumerStatefulWidget {
  const QuickAddBar({super.key});

  @override
  ConsumerState<QuickAddBar> createState() => _QuickAddBarState();
}

class _QuickAddBarState extends ConsumerState<QuickAddBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _isAdding = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleTextChanged);
  }

  void _handleTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty || _isAdding) return;

    setState(() => _isAdding = true);

    await ref
        .read(groceryListControllerProvider.notifier)
        .addItem(name: name, quantity: '1.0');

    if (mounted) {
      if (ref.read(groceryListControllerProvider).hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not add the item. Please try again.'),
          ),
        );
      } else {
        _controller.clear();
      }
      setState(() => _isAdding = false);
      _focusNode.requestFocus();
    }
  }

  // Future<void> _scanBarcode() async {
  //   final String? barcode = await Navigator.push<String>(
  //     context,
  //     MaterialPageRoute(builder: (context) => const BarcodeScannerDialog()),
  //   );
  //
  //   if (barcode != null && barcode.isNotEmpty) {
  //     _controller.text = barcode;
  //     _submit();
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      height: 52,
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainer
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: isDark
              ? theme.colorScheme.outline.withValues(alpha: 0.2)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              readOnly: _isAdding,
              decoration: const InputDecoration(
                hintText: 'Add items to your list...',
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
                fillColor: Colors.transparent,
                isDense: true,
                hintStyle: TextStyle(fontSize: 14),
              ),
              style: TextStyle(
                fontSize: 15,
                color: isDark ? theme.colorScheme.onSurface : null,
              ),
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => _submit(),
            ),
          ),
          if (_isAdding)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_hasText)
            _ActionButton(
              icon: Icons.done,
              onTap: _submit,
              color: theme.colorScheme.primary,
            ),
          // _ActionButton(icon: Icons.qr_code_scanner, onTap: _scanBarcode),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.onTap, this.color});
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        icon,
        size: 20,
        color:
            color ??
            Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
      ),
      onPressed: onTap,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      visualDensity: VisualDensity.compact,
    );
  }
}
