import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/localization_service.dart';
import '../services/product_store_supabase.dart';

/// Диалог выбора продукта из номенклатуры (поиск + опция «новый продукт»).
class NomenclatureProductPickerDialog extends StatefulWidget {
  const NomenclatureProductPickerDialog({
    super.key,
    required this.products,
    required this.lang,
    this.showCreateNew = true,
  });

  final List<Product> products;
  final String lang;
  final bool showCreateNew;

  @override
  State<NomenclatureProductPickerDialog> createState() =>
      _NomenclatureProductPickerDialogState();
}

class _NomenclatureProductPickerDialogState
    extends State<NomenclatureProductPickerDialog> {
  String _query = '';
  final _ctrl = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureTranslations());
  }

  Future<void> _ensureTranslations() async {
    if (!mounted) return;
    final lang = widget.lang;
    if (lang == 'ru') {
      _searchFocus.requestFocus();
      return;
    }
    final store = context.read<ProductStoreSupabase>();
    final missing = widget.products.where(
      (p) =>
          !(p.names?.containsKey(lang) == true &&
              (p.names![lang]?.trim().isNotEmpty ?? false)),
    ).toList();
    if (missing.isEmpty) {
      _searchFocus.requestFocus();
      return;
    }
    for (final p in missing) {
      if (!mounted) break;
      try {
        await store
            .translateProductAwait(p.id)
            .timeout(const Duration(seconds: 5), onTimeout: () => null);
      } catch (_) {}
      if (mounted) setState(() {});
    }
    if (mounted) _searchFocus.requestFocus();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.read<LocalizationService>();

    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.products
        : widget.products.where((p) {
            return p.name.toLowerCase().contains(q) ||
                p.getLocalizedName(widget.lang).toLowerCase().contains(q);
          }).toList();
    return AlertDialog(
      title: Text(loc.t('ttk_choose_product')),
      content: SizedBox(
        width: 400,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ctrl,
              focusNode: _searchFocus,
              decoration: InputDecoration(
                labelText: loc.t('search'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final p = filtered[i];
                  return ListTile(
                    title: Text(
                      p.getLocalizedName(widget.lang),
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => Navigator.of(context).pop(p),
                  );
                },
              ),
            ),
            if (widget.showCreateNew) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop('__new__'),
                icon: const Icon(Icons.add_circle_outline),
                label: Text(loc.t('procurement_product_new')),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
      ],
    );
  }
}
