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

  /// Регистрация нового пользователя
  Future<AuthResponse> signUpWithEmail(String email, String password) async {
    return await client.auth.signUp(
      email: email,
      password: password,
    );
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
      throw Exception('Insert returned no data');
    }
    return response.first;
  }

  /// Обновление данных в таблице
  Future<Map<String, dynamic>> updateData(
    String tableName,
    Map<String, dynamic> data,
    String column,
    dynamic value,
  ) async {
    final response = await client
        .from(tableName)
        .update(data)
        .eq(column, value)
        .select();
    return response.first;
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