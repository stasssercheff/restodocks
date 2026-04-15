import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'flutter_quill_localizations_kk.dart';

/// Supplies [FlutterQuillLocalizations] for `kk` — the upstream package has no Kazakh.
class FlutterQuillKkDelegate extends LocalizationsDelegate<FlutterQuillLocalizations> {
  const FlutterQuillKkDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'kk';

  @override
  Future<FlutterQuillLocalizations> load(Locale locale) {
    return SynchronousFuture<FlutterQuillLocalizations>(
      FlutterQuillLocalizationsKk(),
    );
  }

  @override
  bool shouldReload(covariant FlutterQuillKkDelegate old) => false;
}
