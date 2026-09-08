import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../models/grocery_item_model.dart';
import '../providers/grocery_list_provider.dart';

Future<void> showAddItemDialog(
  BuildContext context, {
  GroceryItem? existingItem,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => AddItemDialog(existingItem: existingItem),
  );
}

class AddItemDialog extends ConsumerStatefulWidget {
  const AddItemDialog({super.key, this.existingItem});

  final GroceryItem? existingItem;

  @override
  ConsumerState<AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends ConsumerState<AddItemDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _quantityController;
  late final TextEditingController _priceController;
  late String _selectedCategory;
  late String _selectedUnit;
  late int _quantity;
  bool _isSubmitting = false;

  bool get _isEditing => widget.existingItem != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existingItem?.name);
    _quantity = int.tryParse(widget.existingItem?.quantity ?? '1') ?? 1;
    _quantityController = TextEditingController(text: _quantity.toString());
    _priceController = TextEditingController(
      text: widget.existingItem?.price != null && widget.existingItem!.price > 0
          ? widget.existingItem!.price.toStringAsFixed(2)
          : '',
    );
    _selectedCategory = widget.existingItem?.category ?? 'Other';
    _selectedUnit = widget.existingItem?.unit ?? 'pcs';
  }

  void _increment() {
    setState(() {
      _quantity++;
      _quantityController.text = _quantity.toString();
    });
  }

  void _decrement() async {
    if (_quantity > 1) {
      setState(() {
        _quantity--;
        _quantityController.text = _quantity.toString();
      });
    } else if (_isEditing) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Item?'),
          content: Text('Remove "${widget.existingItem!.name}"?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) {
        await ref.read(groceryListControllerProvider.notifier).deleteItem(widget.existingItem!.id);
        if (mounted) Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    final controller = ref.read(groceryListControllerProvider.notifier);
    final price = double.tryParse(_priceController.text) ?? 0.0;
    final name = _nameController.text.trim();

    if (_isEditing) {
      await controller.updateItem(
        widget.existingItem!.copyWith(
          name: name,
          quantity: _quantityController.text.trim(),
          category: _selectedCategory,
          unit: _selectedUnit,
          price: price,
          updatedAt: DateTime.now(),
        ),
      );
    } else {
      await controller.addItem(
        name: name,
        quantity: _quantityController.text.trim(),
        category: _selectedCategory,
        unit: _selectedUnit,
        price: price,
      );
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final suggestions = ref.watch(smartSuggestionsProvider).valueOrNull ?? [];

    final backgroundColor = isDark ? const Color(0xFF121411) : Colors.white;
    final inputFillColor = isDark ? const Color(0xFF1B211A) : Colors.grey.shade100;
    final labelStyle = TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: 13,
      color: isDark ? theme.colorScheme.onSurface.withValues(alpha: 0.7) : Colors.black87,
    );

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: backgroundColor,
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isEditing ? 'Edit Item' : 'Add Item',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? theme.colorScheme.onSurface : null,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: isDark ? theme.colorScheme.onSurface : null),
                      onPressed: () => Navigator.pop(context),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Item Name', style: labelStyle),
                const SizedBox(height: 8),
                Autocomplete<String>(
                  initialValue: TextEditingValue(text: _nameController.text),
                  optionsBuilder: (textValue) {
                    if (textValue.text.isEmpty) return const Iterable<String>.empty();
                    return suggestions.where((s) => s.toLowerCase().contains(textValue.text.toLowerCase()));
                  },
                  onSelected: (selection) => _nameController.text = selection,
                  fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                    if (_nameController.text.isNotEmpty && controller.text.isEmpty) {
                      controller.text = _nameController.text;
                    }
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      style: TextStyle(color: isDark ? theme.colorScheme.onSurface : null),
                      decoration: InputDecoration(
                        hintText: 'e.g., Bananas, Milk, Bread',
                        hintStyle: TextStyle(color: isDark ? theme.colorScheme.onSurface.withValues(alpha: 0.3) : null),
                        prefixIcon: Icon(Icons.search, size: 20, color: isDark ? theme.colorScheme.primary : null),
                        filled: true,
                        fillColor: inputFillColor,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      onChanged: (val) => _nameController.text = val,
                      validator: (value) => value == null || value.trim().isEmpty ? 'Enter item name' : null,
                    );
                  },
                ),
                const SizedBox(height: 24),
                Text('Quantity & Unit', style: labelStyle),
                const SizedBox(height: 12),
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: inputFillColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              _quantity > 1 || !_isEditing ? Icons.remove : Icons.delete_outline,
                              size: 18,
                              color: _quantity > 1 || !_isEditing ? (isDark ? theme.colorScheme.onSurface : null) : theme.colorScheme.error,
                            ),
                            onPressed: _decrement,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              _quantity.toString(),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: isDark ? theme.colorScheme.onSurface : null,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.add, size: 18, color: isDark ? theme.colorScheme.onSurface : null),
                            onPressed: _increment,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: ['pcs', 'kg', 'g', 'L', 'pack'].map((unit) {
                          final isSelected = _selectedUnit == unit;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(unit),
                              selected: isSelected,
                              onSelected: (selected) {
                                if (selected) setState(() => _selectedUnit = unit);
                              },
                              backgroundColor: isDark ? inputFillColor : Colors.white,
                              selectedColor: theme.colorScheme.secondary.withValues(alpha: 0.2),
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? theme.colorScheme.secondary
                                    : (isDark ? theme.colorScheme.onSurface.withValues(alpha: 0.5) : Colors.black54),
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              side: BorderSide(
                                color: isSelected
                                    ? theme.colorScheme.secondary
                                    : (isDark ? theme.colorScheme.outline.withValues(alpha: 0.2) : Colors.grey.shade300),
                              ),
                              showCheckmark: false,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Category', style: labelStyle),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedCategory,
                  dropdownColor: backgroundColor,
                  style: TextStyle(color: isDark ? theme.colorScheme.onSurface : Colors.black),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: inputFillColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  items: AppConstants.categories
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(c, style: TextStyle(color: isDark ? theme.colorScheme.onSurface : null)),
                          ))
                      .toList(),
                  onChanged: (val) => setState(() => _selectedCategory = val!),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Price per unit', style: labelStyle),
                    Text('Optional', style: TextStyle(color: theme.colorScheme.primary, fontSize: 11, fontWeight: FontWeight.w500)),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _priceController,
                  textAlign: TextAlign.end,
                  style: TextStyle(color: isDark ? theme.colorScheme.onSurface : null),
                  decoration: InputDecoration(
                    hintText: '0.00',
                    hintStyle: TextStyle(color: isDark ? theme.colorScheme.onSurface.withValues(alpha: 0.3) : null),
                    suffixText: ' EGP',
                    suffixStyle: TextStyle(color: isDark ? theme.colorScheme.onSurface.withValues(alpha: 0.5) : null),
                    filled: true,
                    fillColor: inputFillColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Cancel',
                          style: TextStyle(color: isDark ? theme.colorScheme.onSurface.withValues(alpha: 0.5) : Colors.grey)),
                    ),
                    FilledButton.icon(
                      onPressed: _isSubmitting ? null : _submit,
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.add, size: 18),
                      label: Text(_isEditing ? 'Save' : 'Add '),
                      style: FilledButton.styleFrom(
                        backgroundColor: isDark ? theme.colorScheme.primaryContainer : const Color(0xFF0D631B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
