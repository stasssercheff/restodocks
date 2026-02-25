import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'services.dart';

/// Сервис для работы с документами во входящих
class InboxService {
  final SupabaseService _supabase;

  InboxService(this._supabase);

  /// Получить все документы во входящих для заведения
  Future<List<InboxDocument>> getInboxDocuments(String establishmentId) async {
    final documents = <InboxDocument>[];

    try {
      // Пока возвращаем пустой список - будет доработано позже
      return documents;
    } catch (e) {
      print('Error loading inbox documents: $e');
      return [];
    }
  }

  /// Маппинг секции на отдел
  String _mapSectionToDepartment(String section) {
    switch (section.toLowerCase()) {
      case 'hot_kitchen':
      case 'cold_kitchen':
      case 'confectionery':
        return 'kitchen';
      case 'bar':
        return 'bar';
      case 'hall':
      case 'service':
        return 'hall';
      default:
        return 'management';
    }
  }

  /// Скачать документ
  Future<void> downloadDocument(InboxDocument document) async {
    if (document.fileUrl == null) return;

    try {
      // В реальном приложении здесь будет логика скачивания файла
      // Пока просто имитируем скачивание
      print('Downloading document: ${document.title}');
      print('File URL: ${document.fileUrl}');

      // Можно добавить логику сохранения файла на устройство
      // используя packages как path_provider и http

    } catch (e) {
      print('Error downloading document: $e');
      rethrow;
    }
  }

  /// Получить документы по отделу
  List<InboxDocument> filterByDepartment(List<InboxDocument> documents, String department) {
    if (department == 'all') return documents;
    return documents.where((doc) => doc.department == department).toList();
  }
}