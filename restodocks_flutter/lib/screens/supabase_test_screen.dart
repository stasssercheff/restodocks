import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/services.dart';

/// Диагностика Supabase. Приложение использует свою аутентификацию (сотрудники), а Supabase — только для БД.
class SupabaseTestScreen extends StatefulWidget {
  const SupabaseTestScreen({super.key});

  @override
  State<SupabaseTestScreen> createState() => _SupabaseTestScreenState();
}

class _SupabaseTestScreenState extends State<SupabaseTestScreen> {
  String _status = 'Проверка подключения...';
  bool _isConnected = false;
  String? _errorDetail;
  Map<String, dynamic>? _userInfo;

  @override
  void initState() {
    super.initState();
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    final supabaseService = SupabaseService();
    bool isConnected = false;
    String? errorDetail;
    try {
      isConnected = await supabaseService.isConnected();
      if (!isConnected) errorDetail = 'Запрос к БД завершился с ошибкой.';
    } catch (e) {
      errorDetail = e.toString();
    }
    if (!mounted) return;
    setState(() {
      _isConnected = isConnected;
      _status = isConnected ? '✅ Подключено к Supabase' : '❌ Ошибка подключения';
      _errorDetail = errorDetail;
      _userInfo = {
        'supabase_auth': supabaseService.isAuthenticated,
        'supabase_user': supabaseService.currentUser?.email ?? '—',
        'note': 'Приложение использует вход по PIN/email (сотрудники), не Supabase Auth.',
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

            if (!_isConnected && _errorDetail != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer.withOpacity(0.3),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Что проверить',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Theme.of(context).colorScheme.error,
                            ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '• В Vercel: Project Settings → Environment Variables — заданы SUPABASE_URL и SUPABASE_ANON_KEY для Production и Preview.\n'
                        '• Пересоберите проект после добавления переменных (Redeploy).\n'
                        '• Supabase Dashboard → Settings → API: скопируйте URL и anon key.',
                        style: TextStyle(fontSize: 13),
                      ),
                      if (_errorDetail != null && _errorDetail!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('Ошибка: $_errorDetail', style: const TextStyle(fontSize: 12, color: Colors.red)),
                      ],
                    ],
                  ),
                ),
              ),
            if (_userInfo != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Справка',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow('Supabase Auth:', _userInfo!['supabase_auth'].toString()),
                      _buildInfoRow('Supabase User:', _userInfo!['supabase_user'].toString()),
                      _buildInfoRow('', _userInfo!['note'].toString()),
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
      final establishments = await supabaseService.getData('establishments');
      final products = await supabaseService.getData('products');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'БД доступна: ${establishments.length} заведений, ${products.length} продуктов',
            ),
          ),
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