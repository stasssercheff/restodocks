import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../utils/dev_log.dart';
import 'supabase_service.dart';

/// Сервис документации заведения.
class DocumentationServiceSupabase {
  static final DocumentationServiceSupabase _instance = DocumentationServiceSupabase._internal();
  factory DocumentationServiceSupabase() => _instance;
  DocumentationServiceSupabase._internal();

  final SupabaseService _supabase = SupabaseService();

  /// Документы, видимые текущему сотруднику (по visibility)
  Future<List<EstablishmentDocument>> getDocumentsForEmployee(
    String establishmentId,
    Employee employee,
  ) async {
    try {
      final data = await _supabase.client
          .from('establishment_documents')
          .select()
          .eq('establishment_id', establishmentId)
          .order('updated_at', ascending: false);

      final list = <EstablishmentDocument>[];
      for (final row in data) {
        final doc = EstablishmentDocument.fromJson(Map<String, dynamic>.from(row));
        if (_isVisibleToEmployee(doc, employee)) {
          list.add(doc);
        }
      }
      if (kDebugMode) {
        devLog('DocumentationService: loaded ${list.length} documents for $establishmentId');
      }
      return list;
    } catch (e) {
      devLog('DocumentationService: error $e');
      rethrow;
    }
  }

  bool _isVisibleToEmployee(EstablishmentDocument doc, Employee employee) {
    switch (doc.visibilityType) {
      case DocumentVisibilityType.all:
        return true;
      case DocumentVisibilityType.department:
        final dept = employee.department == 'dining_room' ? 'hall' : employee.department;
        return doc.visibilityIds.contains(dept) || doc.visibilityIds.contains(employee.department);
      case DocumentVisibilityType.section:
        final section = employee.section ?? '';
        return section.isNotEmpty && doc.visibilityIds.contains(section);
      case DocumentVisibilityType.employee:
        return doc.visibilityIds.contains(employee.id);
    }
  }

  Future<EstablishmentDocument?> getDocumentById(String id) async {
    try {
      final row = await _supabase.client
          .from('establishment_documents')
          .select()
          .eq('id', id)
          .limit(1)
          .single();
      return EstablishmentDocument.fromJson(row);
    } catch (e) {
      devLog('DocumentationService: getById error $e');
      return null;
    }
  }

  Future<EstablishmentDocument> createDocument({
    required String establishmentId,
    required String createdBy,
    required String name,
    String? topic,
    DocumentVisibilityType visibilityType = DocumentVisibilityType.all,
    List<String> visibilityIds = const [],
    String? body,
  }) async {
    final row = await _supabase.client
        .from('establishment_documents')
        .insert({
          'establishment_id': establishmentId,
          'created_by': createdBy,
          'name': name,
          'topic': topic,
          'visibility_type': visibilityType.code,
          'visibility_ids': visibilityIds,
          'body': body,
        })
        .select()
        .single();
    return EstablishmentDocument.fromJson(row);
  }

  Future<EstablishmentDocument> updateDocument(EstablishmentDocument doc) async {
    final row = await _supabase.client
        .from('establishment_documents')
        .update({
          'name': doc.name,
          'topic': doc.topic,
          'visibility_type': doc.visibilityType.code,
          'visibility_ids': doc.visibilityIds,
          'body': doc.body,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', doc.id)
        .select()
        .single();
    return EstablishmentDocument.fromJson(row);
  }

  Future<void> deleteDocument(String id) async {
    await _supabase.client.from('establishment_documents').delete().eq('id', id);
  }
}
