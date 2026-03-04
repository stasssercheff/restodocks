import '../models/employee_direct_message.dart';
import 'supabase_service.dart';

/// Сервис личных сообщений между сотрудниками.
class EmployeeMessageService {
  final SupabaseService _supabase = SupabaseService();

  /// Сообщения между текущим сотрудником и другим (двусторонние).
  Future<List<EmployeeDirectMessage>> getMessagesWith(String currentEmployeeId, String otherEmployeeId) async {
    try {
      final sent = await _supabase.client
          .from('employee_direct_messages')
          .select()
          .eq('sender_employee_id', currentEmployeeId)
          .eq('recipient_employee_id', otherEmployeeId)
          .order('created_at', ascending: true);
      final received = await _supabase.client
          .from('employee_direct_messages')
          .select()
          .eq('sender_employee_id', otherEmployeeId)
          .eq('recipient_employee_id', currentEmployeeId)
          .order('created_at', ascending: true);
      final list = <EmployeeDirectMessage>[
        ...(sent as List).map((e) => EmployeeDirectMessage.fromJson(e as Map<String, dynamic>)),
        ...(received as List).map((e) => EmployeeDirectMessage.fromJson(e as Map<String, dynamic>)),
      ];
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return list;
    } catch (e) {
      print('EmployeeMessageService getMessagesWith: $e');
      return [];
    }
  }

  /// Отправить сообщение.
  Future<EmployeeDirectMessage?> send(String senderEmployeeId, String recipientEmployeeId, String content) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;
    try {
      final data = await _supabase.client
          .from('employee_direct_messages')
          .insert({
            'sender_employee_id': senderEmployeeId,
            'recipient_employee_id': recipientEmployeeId,
            'content': trimmed,
          })
          .select()
          .single();
      return EmployeeDirectMessage.fromJson(data);
    } catch (e) {
      print('EmployeeMessageService send: $e');
      rethrow;
    }
  }

  /// Сотрудники, с которыми есть переписка (для списка чатов).
  Future<List<String>> getConversationPartnerIds(String currentEmployeeId, String establishmentId) async {
    try {
      final sent = await _supabase.client
          .from('employee_direct_messages')
          .select('recipient_employee_id')
          .eq('sender_employee_id', currentEmployeeId);
      final received = await _supabase.client
          .from('employee_direct_messages')
          .select('sender_employee_id')
          .eq('recipient_employee_id', currentEmployeeId);
      final ids = <String>{};
      for (final row in sent as List) {
        final id = (row as Map)['recipient_employee_id']?.toString();
        if (id != null && id != currentEmployeeId) ids.add(id);
      }
      for (final row in received as List) {
        final id = (row as Map)['sender_employee_id']?.toString();
        if (id != null && id != currentEmployeeId) ids.add(id);
      }
      return ids.toList();
    } catch (e) {
      print('EmployeeMessageService getConversationPartnerIds: $e');
      return [];
    }
  }
}
