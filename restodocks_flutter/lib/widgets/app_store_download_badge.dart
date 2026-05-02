import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_store_public_url.dart';

/// Официальный бейдж «Download on the App Store» (Apple Marketing).
class AppStoreDownloadBadge extends StatelessWidget {
  const AppStoreDownloadBadge({
    super.key,
    required this.semanticsLabel,
    this.height = 44,
  });

  final String semanticsLabel;
  final double height;

  static const _badgeImageUrl =
      'https://tools.applemediaservices.com/api/badges/download-on-the-app-store/black/en-us?size=250x83';

  @override
  Widget build(BuildContext context) {
    final uri = Uri.parse(appStoreListingUriString);
    return Semantics(
      label: semanticsLabel,
      button: true,
      child: Tooltip(
        message: semanticsLabel,
        child: InkWell(
          onTap: () async {
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            _badgeImageUrl,
            height: height,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => OutlinedButton.icon(
              onPressed: () async {
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.apple, size: 22),
              label: Text(semanticsLabel),
            ),
          ),
        ),
      ),
    );
  }
}
