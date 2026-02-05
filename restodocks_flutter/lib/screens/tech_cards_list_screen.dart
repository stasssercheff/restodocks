import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/ai_service.dart';
import '../services/image_service.dart';
import '../services/services.dart';

/// Список ТТК заведения. Создание и переход к редактированию.
class TechCardsListScreen extends StatefulWidget {
  const TechCardsListScreen({super.key});

  @override
  State<TechCardsListScreen> createState() => _TechCardsListScreenState();
}

class _TechCardsListScreenState extends State<TechCardsListScreen> {
  List<TechCard> _list = [];
  bool _loading = true;
  String? _error;

  String _categoryLabel(String c) {
    const map = {
      'vegetables': 'Овощи', 'fruits': 'Фрукты', 'meat': 'Мясо', 'seafood': 'Рыба',
      'dairy': 'Молочное', 'grains': 'Крупы', 'bakery': 'Выпечка', 'pantry': 'Бакалея',
      'spices': 'Специи', 'beverages': 'Напитки', 'eggs': 'Яйца', 'legumes': 'Бобовые',
      'nuts': 'Орехи', 'misc': '—',
    };
    return map[c] ?? c;
  }

  Future<void> _load() async {
    final acc = context.read<AccountManagerSupabase>();
    final est = acc.establishment;
    if (est == null) {
      setState(() { _loading = false; _error = 'Нет заведения'; });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final svc = context.read<TechCardServiceSupabase>();
      final list = await svc.getTechCardsForEstablishment(est.id);
      if (mounted) setState(() { _list = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _createFromPhoto(BuildContext context, LocalizationService loc) async {
    final imageService = ImageService();
    final xFile = await imageService.pickImageFromGallery();
    if (xFile == null || !mounted) return;
    final bytes = await imageService.xFileToBytes(xFile);
    if (bytes == null || bytes.isEmpty || !mounted) return;
    final ai = context.read<AiService>();
    final result = await ai.recognizeTechCardFromImage(bytes);
    if (!mounted) return;
    if (result == null || (result.dishName == null && result.ingredients.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('ai_tech_card_recognize_empty'))),
      );
      return;
    }
    context.push('/tech-cards/new', extra: result);
  }

  Future<void> _createFromExcel(BuildContext context, LocalizationService loc) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (result == null || result.files.isEmpty || result.files.single.bytes == null || !mounted) return;
    final bytes = result.files.single.bytes!;
    final ai = context.read<AiService>();
    final list = await ai.parseTechCardsFromExcel(Uint8List.fromList(bytes));
    if (!mounted) return;
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.t('ai_tech_card_recognize_empty'))),
      );
      return;
    }
    if (list.length == 1) {
      context.push('/tech-cards/new', extra: list.single);
    } else {
      context.push('/tech-cards/import-review', extra: list);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final canEdit = context.watch<AccountManagerSupabase>().currentEmployee?.canEditChecklistsAndTechCards ?? false;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Text(loc.t('tech_cards')),
        actions: [
          if (canEdit)
            AbsorbPointer(
              absorbing: _loading,
              child: PopupMenuButton<String>(
                icon: Icon(Icons.add, color: _loading ? Theme.of(context).disabledColor : null),
                tooltip: loc.t('create_tech_card'),
                onSelected: (value) async {
                  if (value == 'new') {
                    context.push('/tech-cards/new');
                  } else if (value == 'photo') {
                    await _createFromPhoto(context, loc);
                  } else if (value == 'excel') {
                    await _createFromExcel(context, loc);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'new', child: Text(loc.t('create_tech_card'))),
                  PopupMenuItem(
                    value: 'photo',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(loc.t('ai_tech_card_from_photo')),
                        const SizedBox(width: 8),
                        Chip(label: Text(loc.t('ai_badge'), style: const TextStyle(fontSize: 10)), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'excel',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(loc.t('ai_tech_card_from_excel')),
                        const SizedBox(width: 8),
                        Chip(label: Text(loc.t('ai_badge'), style: const TextStyle(fontSize: 10)), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load, tooltip: loc.t('refresh')),
          IconButton(icon: const Icon(Icons.home), onPressed: () => context.go('/home'), tooltip: loc.t('home')),
        ],
      ),
      body: _buildBody(loc),
      floatingActionButton: canEdit
          ? FloatingActionButton(
              onPressed: _loading ? null : () => context.push('/tech-cards/new'),
              child: const Icon(Icons.add),
              tooltip: loc.t('create_tech_card'),
            )
          : null,
    );
  }

  Widget _buildBody(LocalizationService loc) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: Text(loc.t('refresh'))),
            ],
          ),
        ),
      );
    }
    if (_list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.description, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(loc.t('tech_cards'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(loc.t('tech_cards_empty'), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    final lang = loc.currentLanguageCode;
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(Theme.of(context).colorScheme.primaryContainer),
            columns: [
              const DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text(loc.t('column_name'), style: const TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text(loc.t('column_category'), style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text(loc.t('ingredients_short'), style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text(loc.t('kcal'), style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text(loc.t('output_g'), style: TextStyle(fontWeight: FontWeight.bold))),
              DataColumn(label: Text('', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: List.generate(_list.length, (i) {
              final tc = _list[i];
              return DataRow(
                cells: [
                  DataCell(Text('${i + 1}')),
                  DataCell(Text(tc.getLocalizedDishName(lang))),
                  DataCell(Text(_categoryLabel(tc.category))),
                  DataCell(Text('${tc.ingredients.length}')),
                  DataCell(Text('${tc.totalCalories.round()}')),
                  DataCell(Text(tc.yield.toStringAsFixed(0))),
                  DataCell(IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => context.push('/tech-cards/${tc.id}'),
                  )),
                ],
                onSelectChanged: (_) => context.push('/tech-cards/${tc.id}'),
              );
            }),
          ),
        ),
      ),
    );
  }
}
