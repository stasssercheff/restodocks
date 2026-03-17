import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/dev_log.dart';
import '../models/chat_room.dart';
import '../models/chat_room_message.dart';
import 'image_service.dart';
import 'supabase_service.dart';

/// Сервис групповых чатов.
class GroupChatService {
  final SupabaseService _supabase = SupabaseService();

  static const _chatImagesBucket = 'chat_images';

  /// Создать групповой чат и добавить участников. [memberEmployeeIds] должны включать создателя.
  Future<ChatRoom?> createRoom({
    required String establishmentId,
    required String createdByEmployeeId,
    required List<String> memberEmployeeIds,
    String? name,
  }) async {
    if (memberEmployeeIds.isEmpty) return null;
    try {
      final insertRoom = await _supabase.client
          .from('chat_rooms')
          .insert({
            'establishment_id': establishmentId,
            'created_by_employee_id': createdByEmployeeId,
            'name': name?.trim().isEmpty == true ? null : name?.trim(),
          })
          .select()
          .single();
      final room = ChatRoom.fromJson(insertRoom as Map<String, dynamic>);
      for (final empId in memberEmployeeIds) {
        await _supabase.client.from('chat_room_members').insert({
          'chat_room_id': room.id,
          'employee_id': empId,
        });
      }
      return room;
    } catch (e) {
      devLog('GroupChatService createRoom: $e');
      rethrow;
    }
  }

  /// Переименовать комнату.
  Future<void> renameRoom(String chatRoomId, String newName) async {
    try {
      await _supabase.client
          .from('chat_rooms')
          .update({'name': newName.trim().isEmpty ? null : newName.trim()})
          .eq('id', chatRoomId);
    } catch (e) {
      devLog('GroupChatService renameRoom: $e');
      rethrow;
    }
  }

  /// Список комнат, в которых состоит сотрудник (для заведения).
  Future<List<ChatRoom>> getRoomsForEmployee(String currentEmployeeId, String establishmentId) async {
    try {
      final res = await _supabase.client
          .from('chat_room_members')
          .select('chat_room_id')
          .eq('employee_id', currentEmployeeId);
      final roomIds = (res as List).map((r) => (r as Map)['chat_room_id'] as String).toList();
      if (roomIds.isEmpty) return [];
      final rooms = await _supabase.client
          .from('chat_rooms')
          .select()
          .eq('establishment_id', establishmentId)
          .inFilter('id', roomIds)
          .order('created_at', ascending: false);
      return (rooms as List).map((r) => ChatRoom.fromJson(r as Map<String, dynamic>)).toList();
    } catch (e) {
      devLog('GroupChatService getRoomsForEmployee: $e');
      return [];
    }
  }

  /// Сообщения комнаты.
  Future<List<ChatRoomMessage>> getMessages(String chatRoomId) async {
    try {
      final res = await _supabase.client
          .from('chat_room_messages')
          .select()
          .eq('chat_room_id', chatRoomId)
          .order('created_at', ascending: true);
      return (res as List).map((r) => ChatRoomMessage.fromJson(r as Map<String, dynamic>)).toList();
    } catch (e) {
      devLog('GroupChatService getMessages: $e');
      return [];
    }
  }

  /// Отправить текстовое сообщение.
  Future<ChatRoomMessage?> sendMessage(String chatRoomId, String senderEmployeeId, String content, {String? imageUrl}) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty && (imageUrl == null || imageUrl.isEmpty)) return null;
    try {
      final payload = <String, dynamic>{
        'chat_room_id': chatRoomId,
        'sender_employee_id': senderEmployeeId,
        'content': trimmed,
      };
      if (imageUrl != null && imageUrl.isNotEmpty) payload['image_url'] = imageUrl;
      final data = await _supabase.client
          .from('chat_room_messages')
          .insert(payload)
          .select()
          .single();
      return ChatRoomMessage.fromJson(data as Map<String, dynamic>);
    } catch (e) {
      devLog('GroupChatService sendMessage: $e');
      rethrow;
    }
  }

  /// Отправить фото в групповой чат.
  Future<ChatRoomMessage?> sendPhoto(String chatRoomId, String senderEmployeeId, Uint8List imageBytes) async {
    try {
      final compressed = await ImageService().compressToMaxBytes(imageBytes, maxBytes: 512 * 1024) ?? imageBytes;
      final path = 'group/$chatRoomId/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _supabase.client.storage
          .from(_chatImagesBucket)
          .uploadBinary(path, compressed, fileOptions: const FileOptions(upsert: true));
      final url = _supabase.client.storage.from(_chatImagesBucket).getPublicUrl(path);
      return sendMessage(chatRoomId, senderEmployeeId, '', imageUrl: url);
    } catch (e) {
      devLog('GroupChatService sendPhoto: $e');
      rethrow;
    }
  }

  /// ID участников комнаты (для отображения имён в чате).
  Future<List<String>> getMemberIds(String chatRoomId) async {
    try {
      final res = await _supabase.client
          .from('chat_room_members')
          .select('employee_id')
          .eq('chat_room_id', chatRoomId);
      return (res as List).map((r) => (r as Map)['employee_id'] as String).toList();
    } catch (e) {
      devLog('GroupChatService getMemberIds: $e');
      return [];
    }
  }
}
