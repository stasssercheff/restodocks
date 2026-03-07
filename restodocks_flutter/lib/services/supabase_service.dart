import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Сервис для работы с Supabase
class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();
  factory SupabaseService() => _instance;
  SupabaseService._internal();

  SupabaseClient get client => Supabase.instance.client;

  /// Проверка подключения к Supabase (используем таблицу establishments — она есть в схеме)
  Future<bool> isConnected() async {
    try {
      await client.from('establishments').select('id').limit(1);
      return true;
    } catch (e) {
      print('Supabase connection error: $e');
      return false;
    }
  }

  /// Получение информации о текущем пользователе
  User? get currentUser => client.auth.currentUser;

  /// Проверка аутентификации
  bool get isAuthenticated => currentUser != null;

  /// Вход по email и паролю
  Future<AuthResponse> signInWithEmail(String email, String password) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  /// Регистрация нового пользователя.
  /// [emailRedirectTo] — URL для редиректа после подтверждения (настройте Site URL в Supabase Dashboard).
  Future<AuthResponse> signUpWithEmail(String email, String password, {String? emailRedirectTo}) async {
    if (emailRedirectTo != null) {
      return await client.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: emailRedirectTo,
      );
    }
    return await client.auth.signUp(email: email, password: password);
  }

  /// Выход из системы
  Future<void> signOut() async {
    await client.auth.signOut();
  }

  /// Сброс пароля
  Future<void> resetPassword(String email) async {
    await client.auth.resetPasswordForEmail(email);
  }

  /// Пример работы с таблицами
  /// Получение данных из таблицы
  Future<List<Map<String, dynamic>>> getData(String tableName) async {
    final response = await client.from(tableName).select();
    return response as List<Map<String, dynamic>>;
  }

  /// Вставка данных в таблицу
  Future<Map<String, dynamic>> insertData(String tableName, Map<String, dynamic> data) async {
    print('DEBUG SupabaseService: Inserting into $tableName: $data');
    final response = await client.from(tableName).insert(data).select();
    print('DEBUG SupabaseService: Insert response: $response');
    if (response.isEmpty) {
      throw Exception('Insert into $tableName returned empty response — row was not saved');
    }
    return response.first;
  }

  /// Обновление данных в таблице. Бросает исключение если обновлено 0 строк (RLS/не найден).
  Future<Map<String, dynamic>> updateData(
    String tableName,
    Map<String, dynamic> data,
    String column,
    dynamic value,
  ) async {
    try {
      final response = await client
          .from(tableName)
          .update(data)
          .eq(column, value)
          .select();
      final list = response is List ? response as List : <dynamic>[];
      if (list.isNotEmpty) {
        final first = list.first;
        return first is Map<String, dynamic> ? Map<String, dynamic>.from(first) : {...data, column: value};
      }
      // 0 строк — RLS блокирует или запись не найдена. Показываем ошибку пользователю.
      throw Exception(
        'Не удалось сохранить: нет доступа к записи или она не найдена (таблица $tableName, $column=$value). '
        'Проверьте права доступа (RLS) и что пользователь привязан к заведению.',
      );
    } catch (e) {
      if (e is Exception) rethrow;
      print('DEBUG SupabaseService: updateData error ($tableName): $e');
      rethrow;
    }
  }

  /// Удаление данных из таблицы
  Future<void> deleteData(String tableName, String column, dynamic value) async {
    await client.from(tableName).delete().eq(column, value);
  }

  /// Загрузка файла в Supabase Storage
  Future<String> uploadFile(
    String bucketName,
    String fileName,
    List<int> fileBytes,
  ) async {
    final response = await client.storage.from(bucketName).uploadBinary(
      fileName,
      Uint8List.fromList(fileBytes),
      fileOptions: const FileOptions(upsert: true),
    );
    return response;
  }

  /// Получение URL файла из Supabase Storage
  String getFileUrl(String bucketName, String fileName) {
    return client.storage.from(bucketName).getPublicUrl(fileName);
  }

  /// Удаление файла из Supabase Storage
  Future<void> deleteFile(String bucketName, String fileName) async {
    await client.storage.from(bucketName).remove([fileName]);
  }

  /// Подписка на изменения в таблице (реал-тайм)
  Stream<List<Map<String, dynamic>>> subscribeToTable(String tableName) {
    return client.from(tableName).stream(primaryKey: ['id']);
  }
}