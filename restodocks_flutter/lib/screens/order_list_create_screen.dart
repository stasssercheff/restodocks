import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/services.dart';
import '../utils/supplier_contact_validation.dart';
import '../widgets/app_bar_home_button.dart';

/// Создание поставщика: наименование поставщика, контакты (почта, телефон).
/// Название списка не вводится — используется наименование поставщика.
class OrderListCreateScreen extends StatefulWidget {
  const OrderListCreateScreen({
    super.key,
    this.department = 'kitchen',
    this.returnDraftOnly = false,
  });

  final String department;
  final bool returnDraftOnly;

  @override
  State<OrderListCreateScreen> createState() => _OrderListCreateScreenState();
}

class _OrderListCreateScreenState extends State<OrderListCreateScreen> {
  final _supplierCtrl = TextEditingController();
  final _contactPersonCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  @override
  void dispose() {
    _supplierCtrl.dispose();
    _contactPersonCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _next() {
    final loc = context.read<LocalizationService>();
    final messenger = ScaffoldMessenger.of(context);
    final supplier = _supplierCtrl.text.trim();
    if (supplier.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(loc.t('order_list_supplier_name'))),
      );
      return;
    }
    if (!isValidSupplierEmail(_emailCtrl.text)) {
      messenger.showSnackBar(
        SnackBar(content: Text(loc.t('supplier_invalid_email'))),
      );
      return;
    }
    if (!isValidSupplierPhone(_phoneCtrl.text)) {
      messenger.showSnackBar(
        SnackBar(content: Text(loc.t('supplier_invalid_phone'))),
      );
      return;
    }
    final draft = OrderList(
      id: const Uuid().v4(),
      name: supplier,
      supplierName: supplier,
      contactPerson: _contactPersonCtrl.text.trim().isEmpty
          ? null
          : _contactPersonCtrl.text.trim(),
      email: normalizedSupplierEmailOrNull(_emailCtrl.text),
      phone: normalizedSupplierPhoneOrNull(_phoneCtrl.text),
      department: widget.department,
    );
    if (widget.returnDraftOnly) {
      Navigator.of(context).pop(draft);
      return;
    }
    context.push('/product-order/new/products', extra: draft);
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('order_create_supplier')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _supplierCtrl,
              decoration: InputDecoration(
                labelText: loc.t('order_list_supplier_name'),
                border: const OutlineInputBorder(),
                filled: true,
              ),
              textCapitalization: TextCapitalization.words,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contactPersonCtrl,
              decoration: InputDecoration(
                labelText: loc.t('supplier_contact_person'),
                border: const OutlineInputBorder(),
                filled: true,
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 20),
            Text(
              loc.t('order_list_supplier'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _emailCtrl,
              decoration: InputDecoration(
                labelText: loc.t('order_list_contact_email'),
                border: const OutlineInputBorder(),
                filled: true,
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              decoration: InputDecoration(
                labelText: loc.t('order_list_contact_phone'),
                border: const OutlineInputBorder(),
                filled: true,
                counterText: '',
              ),
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              maxLength: 15,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _next,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(loc.t('order_list_next')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
