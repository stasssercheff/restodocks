import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';

/// Тестовый экран для проверки работы Supabase
class SupabaseTestScreen extends StatefulWidget {
  const SupabaseTestScreen({super.key});

  @override
  State<SupabaseTestScreen> createState() => _SupabaseTestScreenState();
}

class _SupabaseTestScreenState extends State<SupabaseTestScreen> {
  String _status = 'Проверка подключения...';
  bool _isConnected = false;
  Map<String, dynamic>? _userInfo;

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    final supabaseService = SupabaseService();
    final isConnected = await supabaseService.isConnected();

    setState(() {
      _isConnected = isConnected;
      _status = isConnected ? '✅ Подключено к Supabase' : '❌ Ошибка подключения';
      _userInfo = {
        'authenticated': supabaseService.isAuthenticated,
        'user_id': supabaseService.currentUser?.id,
        'email': supabaseService.currentUser?.email,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final localization = context.watch<LocalizationService>();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(localization.t('supabase_test')),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () => context.go('/home'),
            tooltip: localization.t('home'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Статус подключения
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Статус Supabase',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _status,
                      style: TextStyle(
                        color: _isConnected ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Информация о пользователе
            if (_userInfo != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Информация о пользователе',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow('Аутентифицирован:', _userInfo!['authenticated'].toString()),
                      _buildInfoRow('User ID:', _userInfo!['user_id'] ?? 'Не указан'),
                      _buildInfoRow('Email:', _userInfo!['email'] ?? 'Не указан'),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Тестовые кнопки
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Тестовые действия',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton(
                          onPressed: _checkConnection,
                          child: const Text('Проверить подключение'),
                        ),
                        ElevatedButton(
                          onPressed: () => _testDatabase(context),
                          child: const Text('Тест базы данных'),
                        ),
                        ElevatedButton(
                          onPressed: () => _testStorage(context),
                          child: const Text('Тест хранилища'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Информация о конфигурации
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Конфигурация Supabase',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow('URL:', '***'),
                    _buildInfoRow('Ключ:', '***'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  Future<void> _testDatabase(BuildContext context) async {
    try {
      final supabaseService = SupabaseService();
      // Пример запроса к тестовой таблице
      final data = await supabaseService.getData('test_table');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Получено ${data.length} записей из базы данных')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка базы данных: $e')),
        );
      }
    }
  }

  Future<void> _testStorage(BuildContext context) async {
    try {
      final supabaseService = SupabaseService();
      // Пример получения URL файла
      final url = supabaseService.getFileUrl('test-bucket', 'test-file.jpg');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('URL файла: $url')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка хранилища: $e')),
        );
      }
    }
  }
}