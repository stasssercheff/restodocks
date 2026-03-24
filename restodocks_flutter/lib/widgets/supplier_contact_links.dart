import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Ссылки на контакты поставщика: email (mailto:) и телефон (tel:).
class SupplierContactLinks extends StatelessWidget {
  const SupplierContactLinks({
    super.key,
    this.email,
    this.phone,
    this.linkColor,
    this.fontSize = 12,
    this.inline = false,
  });

  final String? email;
  final String? phone;
  final Color? linkColor;
  final double fontSize;
  /// Если true — в одну строку через Wrap, иначе вертикальный Column.
  final bool inline;

  static Future<void> launchMail(String email) async {
    final uri = Uri.parse('mailto:${email.trim()}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  static Future<void> launchPhone(String phone) async {
    final tel = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    final uri = Uri.parse('tel:$tel');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = linkColor ?? Theme.of(context).colorScheme.primary;
    final parts = <Widget>[];
    if (email != null && email!.isNotEmpty) {
      parts.add(
        InkWell(
          onTap: () => launchMail(email!),
          borderRadius: BorderRadius.circular(4),
          child: Text(
            email!,
            style: TextStyle(fontSize: fontSize, color: color, decoration: TextDecoration.underline),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    if (phone != null && phone!.isNotEmpty) {
      if (parts.isNotEmpty && inline) parts.add(const SizedBox(width: 8));
      if (parts.isNotEmpty && !inline) parts.add(const SizedBox(height: 2));
      parts.add(
        InkWell(
          onTap: () => launchPhone(phone!),
          borderRadius: BorderRadius.circular(4),
          child: Text(
            phone!,
            style: TextStyle(fontSize: fontSize, color: color, decoration: TextDecoration.underline),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    if (parts.isEmpty) return const SizedBox.shrink();
    return inline
        ? Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: parts)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: parts,
          );
  }
}
