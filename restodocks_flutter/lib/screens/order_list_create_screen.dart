import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';
import '../services/services.dart';

/// Шаг 1 создания списка заказа: название списка, поставщик (наименование), контакты (почта, телефон, TG, Zalo, WhatsApp).
class OrderListCreateScreen extends StatefulWidget {
  const OrderListCreateScreen({super.key});

  @override
  State<OrderListCreateScreen> createState() => _OrderListCreateScreenState();
}

class _OrderListCreateScreenState extends State<OrderListCreateScreen> {
  final _nameCtrl = TextEditingController();
  final _supplierCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _telegramCtrl = TextEditingController();
  final _zaloCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _supplierCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _telegramCtrl.dispose();
    _zaloCtrl.dispose();
    _whatsappCtrl.dispose();
    super.dispose();
  }

  void _next() {
    final name = _nameCtrl.text.trim();
    final supplier = _supplierCtrl.text.trim();
    if (name.isEmpty || supplier.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.read<LocalizationService>().t('order_list_name'))),
      );
      return;
    }
    final draft = OrderList(
      id: const Uuid().v4(),
      name: name,
      supplierName: supplier,
      email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
      telegram: _telegramCtrl.text.trim().isEmpty ? null : _telegramCtrl.text.trim(),
      zalo: _zaloCtrl.text.trim().isEmpty ? null : _zaloCtrl.text.trim(),
      whatsapp: _whatsappCtrl.text.trim().isEmpty ? null : _whatsappCtrl.text.trim(),
    );
    context.push('/product-order/new/products', extra: draft);
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/product-order')),
        title: Text(loc.t('order_list_create')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: loc.t('order_list_name'),
                border: const OutlineInputBorder(),
                filled: true,
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _supplierCtrl,
              decoration: InputDecoration(
                labelText: loc.t('order_list_supplier_name'),
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
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _telegramCtrl,
              decoration: InputDecoration(
                labelText: loc.t('order_list_contact_telegram'),
                border: const OutlineInputBorder(),
                filled: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _zaloCtrl,
              decoration: InputDecoration(
                labelText: loc.t('order_list_contact_zalo'),
                border: const OutlineInputBorder(),
                filled: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _whatsappCtrl,
              decoration: InputDecoration(
                labelText: loc.t('order_list_contact_whatsapp'),
                border: const OutlineInputBorder(),
                filled: true,
              ),
              keyboardType: TextInputType.phone,
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
