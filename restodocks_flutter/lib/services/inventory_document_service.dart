import 'supabase_service.dart';

/// Сервис документов инвентаризации: сохранение в БД, кабинет шеф-повара.
class InventoryDocumentService {
  static final InventoryDocumentService _instance = InventoryDocumentService._internal();
  factory InventoryDocumentService() => _instance;
  InventoryDocumentService._internal();

  final SupabaseService _supabase = SupabaseService();
  static const _table = 'inventory_documents';

  /// Сохранить документ инвентаризации (после «Завершить»).
  /// [payload] — JSON: { header: {...}, rows: [...] }.
  Future<Map<String, dynamic>?> save({
    required String establishmentId,
    required String createdByEmployeeId,
    required String recipientChefId,
    required String recipientEmail,
    required Map<String, dynamic> payload,
  }) async {
    try {
      final data = <String, dynamic>{
        'establishment_id': establishmentId,
        'created_by_employee_id': createdByEmployeeId,
        'recipient_chef_id': recipientChefId,
        'recipient_email': recipientEmail,
        'payload': payload,
      };
      final raw = await _supabase.client.from(_table).insert(data).select();
      final list = raw as List;
      if (list.isEmpty) return null;
      return Map<String, dynamic>.from(list.first as Map<String, dynamic>);
    } catch (e) {
      print('Ошибка сохранения документа инвентаризации: $e');
      return null;
    }
  }

  /// Отметить, что email отправлен.
  Future<void> markEmailSent(String documentId) async {
    try {
      await _supabase.client
          .from(_table)
          .update({'email_sent_at': DateTime.now().toIso8601String()}).eq('id', documentId);
    } catch (e) {
      print('Ошибка обновления email_sent_at: $e');
    }
  }

  /// Список документов для кабинета шеф-повара (полученные инвентаризации).
  Future<List<Map<String, dynamic>>> listForChef(String recipientChefId) async {
    try {
      final data = await _supabase.client
          .from(_table)
          .select()
          .eq('recipient_chef_id', recipientChefId)
          .order('created_at', ascending: false);

      return (data as List).map((e) => Map<String, dynamic>.from(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Ошибка загрузки документов инвентаризации: $e');
      return [];
    }
  }
}
