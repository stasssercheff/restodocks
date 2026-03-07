import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/employee_direct_message.dart';
import 'image_service.dart';
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

  static const _chatImagesBucket = 'chat_images';

  /// Отправить фото.
  Future<EmployeeDirectMessage?> sendPhoto(
    String senderEmployeeId,
    String recipientEmployeeId,
    Uint8List imageBytes,
  ) async {
    try {
      final compressed = await ImageService().compressToMaxBytes(imageBytes, maxBytes: 512 * 1024) ?? imageBytes;
      final path = '$senderEmployeeId/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _supabase.client.storage
          .from(_chatImagesBucket)
          .uploadBinary(path, compressed, fileOptions: const FileOptions(upsert: true));
      final url = _supabase.client.storage.from(_chatImagesBucket).getPublicUrl(path);
      return send(senderEmployeeId, recipientEmployeeId, '', imageUrl: url);
    } catch (e) {
      print('EmployeeMessageService sendPhoto: $e');
      rethrow;
    }
  }

  /// Отправить сообщение.
  Future<EmployeeDirectMessage?> send(
    String senderEmployeeId,
    String recipientEmployeeId,
    String content, {
    String? imageUrl,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty && (imageUrl == null || imageUrl.isEmpty)) return null;
    try {
      final payload = <String, dynamic>{
        'sender_employee_id': senderEmployeeId,
        'recipient_employee_id': recipientEmployeeId,
        'content': trimmed,
      };
      if (imageUrl != null && imageUrl.isNotEmpty) payload['image_url'] = imageUrl;
      final data = await _supabase.client
          .from('employee_direct_messages')
          .insert(payload)
          .select()
          .single();
      return EmployeeDirectMessage.fromJson(data);
    } catch (e) {
      print('EmployeeMessageService send: $e');
      rethrow;
    }
  }

  /// Отметить сообщения от [senderId] как прочитанные (вызывать при открытии чата).
  Future<void> markAsRead(String currentEmployeeId, String senderId) async {
    try {
      await _supabase.client
          .from('employee_direct_messages')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('recipient_employee_id', currentEmployeeId)
          .eq('sender_employee_id', senderId)
          .isFilter('read_at', null);
    } catch (e) {
      print('EmployeeMessageService markAsRead: $e');
    }
  }

  /// Количество непрочитанных сообщений по каждому диалогу (partnerId -> count).
  Future<Map<String, int>> getUnreadCountPerPartner(String currentEmployeeId, String establishmentId) async {
    try {
      final received = await _supabase.client
          .from('employee_direct_messages')
          .select('sender_employee_id')
          .eq('recipient_employee_id', currentEmployeeId)
          .isFilter('read_at', null);
      final counts = <String, int>{};
      for (final row in received as List) {
        final id = (row as Map)['sender_employee_id']?.toString();
        if (id != null && id != currentEmployeeId) {
          counts[id] = (counts[id] ?? 0) + 1;
        }
      }
      return counts;
    } catch (e) {
      print('EmployeeMessageService getUnreadCountPerPartner: $e');
      return {};
    }
  }

  /// Общее количество диалогов с непрочитанными сообщениями (для бейджа).
  Future<int> getUnreadConversationsCount(String currentEmployeeId, String establishmentId) async {
    final map = await getUnreadCountPerPartner(currentEmployeeId, establishmentId);
    return map.length;
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
