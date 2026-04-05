import 'package:flutter/material.dart';

import '../services/apple_email_prefill.dart';
import '../services/localization_service.dart';

/// iOS: подставить в поле только email из Apple. Имя/фамилия/пароль — только из формы.
class AppleEmailPrefillButton extends StatelessWidget {
  const AppleEmailPrefillButton({
    super.key,
    required this.controller,
    required this.localization,
  });

  final TextEditingController controller;
  final LocalizationService localization;

  @override
  Widget build(BuildContext context) {
    if (!AppleEmailPrefill.isSupported) {
      return const SizedBox.shrink();
    }
    final loc = localization;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: () async {
          final email = await AppleEmailPrefill.requestEmailFromApple();
          if (!context.mounted) return;
          if (email != null && email.isNotEmpty) {
            controller.text = email;
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(loc.t('register_apple_email_unavailable'))),
            );
          }
        },
        icon: const Icon(Icons.apple, size: 18),
        label: Text(loc.t('register_prefill_email_from_apple')),
      ),
    );
  }
}
