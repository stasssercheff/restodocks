import 'package:flutter/material.dart';

import '../services/localization_service.dart';
import '../utils/establishment_currency_options.dart';

/// Диалог выбора валюты заведения (тот же список, что в настройках).
/// Поиск по коду, названию валюты и стране; [AlertDialog] — стабильнее на Web.
Future<void> showEstablishmentCurrencyPickerDialog({
  required BuildContext context,
  required LocalizationService loc,
  required String currentCode,
  required Future<void> Function(String isoCode) onApply,
}) async {
  final customController = TextEditingController();
  final searchController = TextEditingController();
  var useOther = !EstablishmentCurrencyOptions.isKnownPreset(currentCode);
  if (useOther) customController.text = currentCode.toUpperCase();

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx2, setDialogState) {
          final upperCurrent = currentCode.toUpperCase();
          final filtered =
              EstablishmentCurrencyOptions.filterPresets(searchController.text);

          Future<void> applyAndClose(String code) async {
            try {
              await onApply(code);
              if (ctx2.mounted) Navigator.of(ctx2).pop();
            } catch (e, st) {
              debugPrint('establishment currency onApply: $e $st');
              if (ctx2.mounted) {
                ScaffoldMessenger.of(ctx2).showSnackBar(
                  SnackBar(
                    content: Text(
                      e is Exception ? e.toString() : 'Error: $e',
                    ),
                  ),
                );
              }
            }
          }

          return AlertDialog(
            title: Text(loc.t('currency')),
            content: SizedBox(
              width: 420,
              height: 460,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CheckboxListTile(
                    value: useOther,
                    onChanged: (v) =>
                        setDialogState(() => useOther = v ?? false),
                    title: Text(
                      loc.t('custom_currency'),
                      style: const TextStyle(fontSize: 14),
                    ),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (useOther) ...[
                    TextField(
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
                  ] else ...[
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: loc.t('currency_search_hint'),
                        prefixIcon: const Icon(Icons.search, size: 22),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: filtered.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    loc.t('currency_search_empty'),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )
                            : ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: filtered.length,
                          itemBuilder: (context, i) {
                            final c = filtered[i];
                            final code = c['code']!;
                            final symbol = c['symbol']!;
                            final name = c['name']!;
                            final country = c['country'] ?? '';
                            final selected = upperCurrent == code;
                            return ListTile(
                              dense: true,
                              leading: Text(
                                symbol,
                                style: const TextStyle(fontSize: 20),
                              ),
                              title: Text('$code — $name'),
                              subtitle: country.isEmpty
                                  ? null
                                  : Text(
                                      country,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                              trailing: selected
                                  ? const Icon(Icons.check, color: Colors.green)
                                  : null,
                              onTap: () => applyAndClose(code),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              if (useOther)
                TextButton(
                  onPressed: () => Navigator.of(ctx2).pop(),
                  child: Text(
                    MaterialLocalizations.of(ctx2).cancelButtonLabel,
                  ),
                ),
              if (useOther)
                FilledButton(
                  onPressed: () async {
                    final code =
                        customController.text.trim().toUpperCase();
                    if (code.length != 3) return;
                    await applyAndClose(code);
                  },
                  child: Text(loc.t('save')),
                ),
              if (!useOther)
                TextButton(
                  onPressed: () => Navigator.of(ctx2).pop(),
                  child: Text(loc.t('close')),
                ),
            ],
          );
        },
      );
    },
  );
  searchController.dispose();
  customController.dispose();
}
