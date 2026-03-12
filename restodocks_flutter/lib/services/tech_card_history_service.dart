import '../utils/dev_log.dart';
import 'supabase_service.dart';
import '../models/models.dart';

/// Запись истории ТТК
class TechCardHistoryEntry {
  final String id;
  final DateTime changedAt;
  final String? changedByEmployeeId;
  final String? changedByName;
  final List<Map<String, dynamic>> changes;

  const TechCardHistoryEntry({
    required this.id,
    required this.changedAt,
    this.changedByEmployeeId,
    this.changedByName,
    required this.changes,
  });

  factory TechCardHistoryEntry.fromJson(Map<String, dynamic> json) {
    final changesList = json['changes'] as List<dynamic>? ?? [];
    return TechCardHistoryEntry(
      id: json['id'] as String? ?? '',
      changedAt: json['changed_at'] != null
          ? DateTime.parse(json['changed_at'] as String)
          : DateTime.now(),
      changedByEmployeeId: json['changed_by_employee_id'] as String?,
      changedByName: json['changed_by_name'] as String?,
      changes: changesList.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );
  }
}

/// Сервис истории изменений ТТК
class TechCardHistoryService {
  final SupabaseService _supabase = SupabaseService();

  /// Сохранить историю изменений при сохранении ТТК
  Future<void> saveHistory({
    required String techCardId,
    required String establishmentId,
    required TechCard? oldCard,
    required TechCard newCard,
    String? changedByEmployeeId,
    String? changedByName,
  }) async {
    try {
      final changes = _buildChanges(oldCard, newCard);
      if (changes.isEmpty) return;

      await _supabase.client.from('tech_card_history').insert({
        'tech_card_id': techCardId,
        'establishment_id': establishmentId,
        'changed_by_employee_id': changedByEmployeeId,
        'changed_by_name': changedByName,
        'changes': changes,
      });
    } catch (e) {
      devLog('TechCardHistoryService: Failed to save history: $e');
    }
  }

  /// Построить список изменений при сравнении старой и новой карточки
  List<Map<String, dynamic>> _buildChanges(TechCard? oldCard, TechCard newCard) {
    final changes = <Map<String, dynamic>>[];
    final lang = 'ru';

    if (oldCard == null) {
      changes.add({'type': 'created', 'label': 'Создана карточка'});
      return changes;
    }

    // Вес порции
    if ((oldCard.portionWeight - newCard.portionWeight).abs() > 0.001) {
      changes.add({
        'type': 'portion_weight',
        'label': 'Вес порции',
        'old': oldCard.portionWeight,
        'new': newCard.portionWeight,
      });
    }

    // Выход
    if ((oldCard.yield - newCard.yield).abs() > 0.001) {
      changes.add({
        'type': 'yield',
        'label': 'Выход',
        'old': oldCard.yield,
        'new': newCard.yield,
      });
    }

    // Название
    final oldName = oldCard.getLocalizedDishName(lang);
    final newName = newCard.getLocalizedDishName(lang);
    if (oldName != newName) {
      changes.add({'type': 'dish_name', 'label': 'Название', 'old': oldName, 'new': newName});
    }

    // Технология
    final oldTech = oldCard.getLocalizedTechnology(lang);
    final newTech = newCard.getLocalizedTechnology(lang);
    if (oldTech != newTech) {
      changes.add({'type': 'technology', 'label': 'Технология', 'changed': true});
    }

    // Ингредиенты
    final oldByName = {for (final i in oldCard.ingredients) i.productName: i};
    final newByName = {for (final i in newCard.ingredients) i.productName: i};

    for (final name in newByName.keys) {
      final newIng = newByName[name]!;
      final oldIng = oldByName[name];
      if (oldIng == null) {
        changes.add({
          'type': 'ingredient_added',
          'label': 'Добавлен продукт',
          'product': name,
          'gross': newIng.grossWeight,
          'net': newIng.netWeight,
        });
      } else {
        final ingChanges = <Map<String, dynamic>>[];
        if ((oldIng.grossWeight - newIng.grossWeight).abs() > 0.001) {
          ingChanges.add({'field': 'брутто', 'old': oldIng.grossWeight, 'new': newIng.grossWeight});
        }
        if ((oldIng.netWeight - newIng.netWeight).abs() > 0.001) {
          ingChanges.add({'field': 'нетто', 'old': oldIng.netWeight, 'new': newIng.netWeight});
        }
        if ((oldIng.primaryWastePct - newIng.primaryWastePct).abs() > 0.001) {
          ingChanges.add({'field': '% отхода', 'old': oldIng.primaryWastePct, 'new': newIng.primaryWastePct});
        }
        final oldLoss = oldIng.cookingLossPctOverride ?? 0.0;
        final newLoss = newIng.cookingLossPctOverride ?? 0.0;
        if ((oldLoss - newLoss).abs() > 0.001) {
          ingChanges.add({'field': '% ужарки', 'old': oldLoss, 'new': newLoss});
        }
        if (ingChanges.isNotEmpty) {
          changes.add({
            'type': 'ingredient_modified',
            'label': 'Изменён продукт',
            'product': name,
            'details': ingChanges,
          });
        }
      }
    }
    for (final name in oldByName.keys) {
      if (!newByName.containsKey(name)) {
        changes.add({'type': 'ingredient_removed', 'label': 'Удалён продукт', 'product': name});
      }
    }

    return changes;
  }

  /// Получить историю изменений ТТК
  Future<List<TechCardHistoryEntry>> getHistory(String techCardId) async {
    try {
      final response = await _supabase.client
          .from('tech_card_history')
          .select('id, changed_at, changed_by_employee_id, changed_by_name, changes')
          .eq('tech_card_id', techCardId)
          .order('changed_at', ascending: false)
          .limit(50);

      final list = response is List ? response : <dynamic>[];
      return list.map((e) => TechCardHistoryEntry.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (e) {
      devLog('TechCardHistoryService: Failed to load history: $e');
      return [];
    }
  }
}
