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
          child: OutlinedButton.icon(
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
    );
  }
}
