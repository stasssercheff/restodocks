import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/models.dart';
import '../services/services.dart';

/// Подтверждение PIN + email и вызов [AccountManagerSupabase.deleteEstablishment].
Future<void> showDeleteEstablishmentFlow(
  BuildContext context, {
  required Establishment establishment,
  required LocalizationService loc,
  required AccountManagerSupabase accountManager,
  required void Function(List<Establishment> remaining) onCompleted,
}) async {
  final ownerEmail = accountManager.currentEmployee?.email ?? '';
  final pinController = TextEditingController();
  final emailController = TextEditingController(text: ownerEmail);
  final formKey = GlobalKey<FormState>();

  final result = await showDialog<String?>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: Text(loc.t('delete_establishment')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${establishment.name}\n\n${loc.t('delete_establishment_enter_pin_email')}',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Form(
              key: formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: pinController,
                    obscureText: true,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: loc.t('company_pin'),
                      hintText: loc.t('enter_company_pin'),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return loc.t('company_pin_required');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: loc.t('email'),
                      hintText: loc.t('enter_email'),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return loc.t('email_required');
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(null),
          child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
        ),
        ElevatedButton(
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            final pin = pinController.text.trim();
            final email = emailController.text.trim();
            if (!establishment.verifyPinCode(pin)) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text(loc.t('delete_establishment_wrong_pin'))),
              );
              return;
            }
            Navigator.of(ctx).pop('$pin|$email');
          },
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: Text(loc.t('delete_establishment')),
        ),
      ],
    ),
  );

  pinController.dispose();
  emailController.dispose();

  if (result == null || !context.mounted) return;
  final parts = result.split('|');
  if (parts.length != 2) return;
  final pin = parts[0];
  final email = parts[1];

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      content: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Expanded(child: Text(loc.t('delete_establishment_progress'))),
        ],
      ),
    ),
  );

  try {
    await accountManager.deleteEstablishment(
      establishmentId: establishment.id,
      pinCode: pin,
      email: email,
    );
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    final remaining = await accountManager.getEstablishmentsForOwner();
    if (context.mounted) onCompleted(remaining);
  } catch (e) {
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    if (!context.mounted) return;
    final msg = e.toString();
    final lower = msg.toLowerCase();
    var snack = loc.t('delete_establishment_wrong_pin');
    if (lower.contains('email does not match') ||
        lower.contains('email не совпадает') ||
        (lower.contains('email') && lower.contains('match'))) {
      snack = loc.t('delete_establishment_wrong_email');
    } else if (!lower.contains('invalid pin') &&
        !lower.contains('pin code') &&
        !lower.contains('неверный') &&
        !lower.contains('wrong pin')) {
      snack = loc.t('delete_establishment_failed');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(snack), backgroundColor: Colors.red),
    );
  }
}

/// После удаления заведения: выход или обновление списка + переход домой.
Future<void> handleEstablishmentDeletedNavigation(
  BuildContext context,
  AccountManagerSupabase accountManager,
  List<Establishment> remaining,
  LocalizationService loc,
) async {
  if (remaining.isEmpty) {
    await accountManager.logout();
    if (context.mounted) context.go('/login');
    return;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(loc.t('delete_establishment_done')),
        backgroundColor: Colors.green,
      ),
    );
    context.go('/home', extra: {'back': true});
  }
}
