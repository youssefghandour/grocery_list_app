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
  bool _isSubmitting = false;

  bool get _isEditing => widget.existingItem != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.existingItem?.name);
    _quantityController =
        TextEditingController(text: widget.existingItem?.quantity ?? '1');
    _priceController = TextEditingController(
      text: widget.existingItem?.price != null && widget.existingItem!.price > 0
          ? widget.existingItem!.price.toStringAsFixed(2)
          : '',
    );
    _selectedCategory = widget.existingItem?.category ?? AppConstants.categories.last; // Default to 'Other'
    _selectedUnit = widget.existingItem?.unit ?? 'pcs';
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

    if (_isEditing) {
      await controller.updateItem(
        widget.existingItem!.copyWith(
          name: _nameController.text.trim(),
          quantity: _quantityController.text.trim(),
          category: _selectedCategory,
          unit: _selectedUnit,
          price: price,
          updatedAt: DateTime.now(),
        ),
      );
    } else {
      await controller.addItem(
        name: _nameController.text.trim(),
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
    final suggestions = ref.watch(smartSuggestionsProvider).valueOrNull ?? [];

    return AlertDialog(
      title: Text(_isEditing ? 'Edit Item' : 'Add Item'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Autocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return const Iterable<String>.empty();
                  }
                  return suggestions.where((String option) {
                    return option.toLowerCase().contains(
                          textEditingValue.text.toLowerCase(),
                        );
                  });
                },
                onSelected: (String selection) {
                  _nameController.text = selection;
                },
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  // Sync local controller with autocomplete controller if needed
                  // For simplicity, we'll just use the autocomplete's controller for name
                  _nameController.text = controller.text.isEmpty ? _nameController.text : controller.text;
                  controller.text = _nameController.text;

                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Item name',
                      hintText: 'e.g. Milk',
                    ),
                    textCapitalization: TextCapitalization.sentences,
                    autofocus: !_isEditing,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Enter an item name';
                      }
                      return null;
                    },
                  );
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _quantityController,
                      decoration: const InputDecoration(
                        labelText: 'Qty',
                      ),
                      keyboardType: TextInputType.text,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedUnit,
                      decoration: const InputDecoration(labelText: 'Unit'),
                      items: AppConstants.units
                          .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                          .toList(),
                      onChanged: (val) => setState(() => _selectedUnit = val!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: const InputDecoration(labelText: 'Category'),
                items: AppConstants.categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (val) => setState(() => _selectedCategory = val!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceController,
                decoration: const InputDecoration(
                  labelText: 'Price (optional)',
                  prefixText: 'EGP ',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
