import 'package:flutter/material.dart';

import '../services/localization_service.dart';
import '../utils/establishment_currency_options.dart';

/// Диалог выбора валюты заведения (тот же список, что в настройках).
Future<void> showEstablishmentCurrencyPickerDialog({
  required BuildContext context,
  required LocalizationService loc,
  required String currentCode,
  required Future<void> Function(String isoCode) onApply,
}) async {
  final customController = TextEditingController();
  var useOther = !EstablishmentCurrencyOptions.isKnownPreset(currentCode);
  if (useOther) customController.text = currentCode.toUpperCase();

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx2, setDialogState) {
          final upperCurrent = currentCode.toUpperCase();
          return Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints:
                    const BoxConstraints(maxWidth: 400, maxHeight: 520),
                decoration: BoxDecoration(
                  color: Theme.of(ctx2).dialogBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: Text(
                        loc.t('currency'),
                        style: Theme.of(ctx2).textTheme.titleMedium,
                      ),
                    ),
                    CheckboxListTile(
                      value: useOther,
                      onChanged: (v) =>
                          setDialogState(() => useOther = v ?? false),
                      title: Text(
                        loc.t('custom_currency'),
                        style: const TextStyle(fontSize: 14),
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    if (useOther)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: TextField(
                          controller: customController,
                          decoration: InputDecoration(
                            labelText: loc.t('currency_code'),
                            hintText: loc.t('currency_hint'),
                            border: const OutlineInputBorder(),
                          ),
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 3,
                          onChanged: (_) => setDialogState(() {}),
                        ),
                      )
                    else
                      SizedBox(
                        height: 360,
                        child: ListView(
                          shrinkWrap: true,
                          children: EstablishmentCurrencyOptions.all.map((c) {
                            final code = c['code']!;
                            final symbol = c['symbol']!;
                            final name = c['name']!;
                            final selected = upperCurrent == code;
                            return ListTile(
                              leading: Text(
                                symbol,
                                style: const TextStyle(fontSize: 20),
                              ),
                              title: Text('$code — $name'),
                              trailing: selected
                                  ? const Icon(Icons.check, color: Colors.green)
                                  : null,
                              onTap: () async {
                                await onApply(code);
                                if (ctx2.mounted) Navigator.of(ctx2).pop();
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    if (useOther)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx2).pop(),
                              child: Text(MaterialLocalizations.of(ctx2)
                                  .cancelButtonLabel),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () async {
                                final code = customController.text
                                    .trim()
                                    .toUpperCase();
                                if (code.length != 3) return;
                                await onApply(code);
                                if (ctx2.mounted) Navigator.of(ctx2).pop();
                              },
                              child: Text(loc.t('save')),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  ).then((_) => customController.dispose());
}
