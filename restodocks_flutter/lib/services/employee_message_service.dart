import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/dev_log.dart';

import '../models/employee_direct_message.dart';
import '../models/employee_message_system_link.dart';
import '../utils/chat_system_link_paths.dart';
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
      devLog('EmployeeMessageService getMessagesWith: $e');
      return [];
    }
  }

  static const _chatImagesBucket = 'chat_images';
  static const _chatVoiceBucket = 'chat_voice';

  /// Макс. размер загрузки (согласовано с лимитом бакета `chat_voice`, см. миграцию).
  static const int maxChatVoiceUploadBytes = 3 * 1024 * 1024;

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
      devLog('EmployeeMessageService sendPhoto: $e');
      rethrow;
    }
  }

  /// Отправить голосовое сообщение (aac в контейнере m4a).
  ///
  /// Передача в Supabase идёт по HTTPS (TLS). Отдельное сквозное шифрование файла
  /// у получателя без расшифровки на стороне клиента здесь не делается.
  Future<EmployeeDirectMessage?> sendVoiceBytes(
    String senderEmployeeId,
    String recipientEmployeeId,
    Uint8List bytes,
    int durationSeconds,
  ) async {
    if (durationSeconds < 1 || bytes.isEmpty) return null;
    if (bytes.length > maxChatVoiceUploadBytes) {
      devLog(
        'EmployeeMessageService sendVoiceBytes: file too large '
        '(${bytes.length} > $maxChatVoiceUploadBytes)',
      );
      return null;
    }
    try {
      final objectPath = '$senderEmployeeId/${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _supabase.client.storage.from(_chatVoiceBucket).uploadBinary(
            objectPath,
            bytes,
            fileOptions: const FileOptions(
              upsert: true,
              contentType: 'audio/mp4',
            ),
          );
      final url = _supabase.client.storage.from(_chatVoiceBucket).getPublicUrl(objectPath);
      return send(
        senderEmployeeId,
        recipientEmployeeId,
        '',
        audioUrl: url,
        audioDurationSeconds: durationSeconds,
      );
    } catch (e) {
      devLog('EmployeeMessageService sendVoiceBytes: $e');
      rethrow;
    }
  }

  /// Отправить сообщение.
  Future<EmployeeDirectMessage?> send(
    String senderEmployeeId,
    String recipientEmployeeId,
    String content, {
    String? imageUrl,
    String? audioUrl,
    int? audioDurationSeconds,
    List<EmployeeMessageSystemLink>? systemLinks,
  }) async {
    final trimmed = content.trim();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final hasAudio = audioUrl != null && audioUrl.isNotEmpty;
    final links = sanitizeSystemLinks(systemLinks);
    final hasLinks = links.isNotEmpty;
    if (trimmed.isEmpty && !hasImage && !hasAudio && !hasLinks) return null;
    try {
      final payload = <String, dynamic>{
        'sender_employee_id': senderEmployeeId,
        'recipient_employee_id': recipientEmployeeId,
        'content': trimmed,
      };
      if (hasImage) payload['image_url'] = imageUrl;
      if (hasAudio) {
        payload['audio_url'] = audioUrl;
        if (audioDurationSeconds != null && audioDurationSeconds > 0) {
          payload['audio_duration_seconds'] = audioDurationSeconds;
        }
      }
      if (hasLinks) {
        payload['system_links'] = links.map((e) => e.toJson()).toList();
      }
      final data = await _supabase.client
          .from('employee_direct_messages')
          .insert(payload)
          .select()
          .single();
      return EmployeeDirectMessage.fromJson(data);
    } catch (e) {
      devLog('EmployeeMessageService send: $e');
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
      devLog('EmployeeMessageService markAsRead: $e');
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
      devLog('EmployeeMessageService getUnreadCountPerPartner: $e');
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
      devLog('EmployeeMessageService getConversationPartnerIds: $e');
      return [];
    }
  }
}
