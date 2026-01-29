import '../models/models.dart';
import 'supabase_service.dart';

/// Сервис чеклистов-шаблонов (Supabase).
class ChecklistServiceSupabase {
  static final ChecklistServiceSupabase _instance = ChecklistServiceSupabase._internal();
  factory ChecklistServiceSupabase() => _instance;
  ChecklistServiceSupabase._internal();

  final SupabaseService _supabase = SupabaseService();

  Future<List<Checklist>> getChecklistsForEstablishment(String establishmentId) async {
    try {
      final data = await _supabase.client
          .from('checklists')
          .select()
          .eq('establishment_id', establishmentId)
          .order('updated_at', ascending: false);

      final list = <Checklist>[];
      for (final row in data) {
        final c = Checklist.fromJson(row);
        final itemsData = await _supabase.client
            .from('checklist_items')
            .select()
            .eq('checklist_id', c.id)
            .order('sort_order');
        final items = (itemsData as List).map((e) => ChecklistItem.fromJson(e)).toList();
        list.add(c.copyWith(items: items));
      }
      return list;
    } catch (e) {
      print('Ошибка загрузки чеклистов: $e');
      return [];
    }
  }

  Future<Checklist?> getChecklistById(String id) async {
    try {
      final row = await _supabase.client
          .from('checklists')
          .select()
          .eq('id', id)
          .limit(1)
          .single();
      final c = Checklist.fromJson(row);
      final itemsData = await _supabase.client
          .from('checklist_items')
          .select()
          .eq('checklist_id', c.id)
          .order('sort_order');
      final items = (itemsData as List).map((e) => ChecklistItem.fromJson(e)).toList();
      return c.copyWith(items: items);
    } catch (e) {
      print('Ошибка загрузки чеклиста: $e');
      return null;
    }
  }

  Future<Checklist> createChecklist({
    required String establishmentId,
    required String createdBy,
    required String name,
    List<ChecklistItem> items = const [],
  }) async {
    final now = DateTime.now();
    final data = {
      'establishment_id': establishmentId,
      'created_by': createdBy,
      'name': name,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
    final res = await _supabase.insertData('checklists', data);
    final c = Checklist.fromJson(res);

    for (var i = 0; i < items.length; i++) {
      await _supabase.insertData('checklist_items', {
        'checklist_id': c.id,
        'title': items[i].title,
        'sort_order': i,
      });
    }
    return (await getChecklistById(c.id)) ?? c;
  }

  Future<void> saveChecklist(Checklist checklist) async {
    await _supabase.updateData(
      'checklists',
      {
        'name': checklist.name,
        'updated_at': DateTime.now().toIso8601String(),
      },
      'id',
      checklist.id,
    );
    await _supabase.client
        .from('checklist_items')
        .delete()
        .eq('checklist_id', checklist.id);
    for (var i = 0; i < checklist.items.length; i++) {
      await _supabase.insertData('checklist_items', {
        'checklist_id': checklist.id,
        'title': checklist.items[i].title,
        'sort_order': i,
      });
    }
  }

  Future<void> deleteChecklist(String id) async {
    await _supabase.deleteData('checklists', 'id', id);
  }

  /// Создать по аналогии (дубликат шаблона).
  Future<Checklist> duplicateChecklist(Checklist source, String createdBy) async {
    return createChecklist(
      establishmentId: source.establishmentId,
      createdBy: createdBy,
      name: '${source.name} (копия)',
      items: source.items
          .map((e) => ChecklistItem.template(title: e.title, sortOrder: e.sortOrder))
          .toList(),
    );
  }
}
