import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/localization_service.dart';
import '../widgets/app_bar_home_button.dart';

/// Статический FAQ: только реализованные функции; тексты — из localizable.json.
class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  static const int _itemCount = 12;

  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(String title, String body, String q) {
    if (q.isEmpty) return true;
    final t = '${title.toLowerCase()} ${body.toLowerCase()}';
    return t.contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final q = _query.trim().toLowerCase();

    final items = <({int index, String title, String body})>[];
    for (var i = 1; i <= _itemCount; i++) {
      final key = i.toString().padLeft(2, '0');
      final title = loc.t('faq_item_${key}_title');
      final body = loc.t('faq_item_${key}_body');
      if (_matches(title, body, q)) {
        items.add((index: i, title: title, body: body));
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: shellReturnLeading(context) ??
            (GoRouter.of(context).canPop()
                ? appBarBackButton(context)
                : null),
        title: Text(loc.t('faq_title')),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              loc.t('faq_subtitle'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: loc.t('faq_search_hint'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        loc.t('faq_no_results'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final e = items[i];
                      return ExpansionTile(
                        key: ValueKey('faq_${e.index}'),
                        title: Text(e.title),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),
                        children: [
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: SelectableText(
                              e.body,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
