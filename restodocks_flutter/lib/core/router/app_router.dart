import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../screens/screens.dart';
import '../../screens/company_registration_screen.dart';
import '../../screens/owner_registration_screen.dart';
import '../../screens/home/schedule_screen.dart';
import '../../screens/home/notifications_screen.dart';
import '../../screens/home/expenses_placeholder_screen.dart';
import '../../screens/home/department_placeholder_screen.dart';
import '../../screens/supabase_test_screen.dart';
import '../../screens/checklists_screen.dart';
import '../../screens/checklist_edit_screen.dart';
import '../../screens/tech_cards_list_screen.dart';
import '../../screens/tech_card_edit_screen.dart';
import '../../screens/order_lists_screen.dart';
import '../../screens/order_list_create_screen.dart';
import '../../screens/order_list_products_screen.dart';
import '../../screens/order_list_detail_screen.dart';
import '../../models/order_list.dart';
import '../../services/ai_service.dart';
import '../../services/services.dart';

const _publicPaths = ['/', '/splash', '/login', '/register', '/register-company', '/register-owner', '/register-employee'];

/// Настройка маршрутизации приложения
class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/',
    redirect: (context, state) async {
      final loc = state.matchedLocation;
      if (_publicPaths.any((p) => loc.startsWith(p))) return null;
      final account = context.read<AccountManagerSupabase>();
      await account.initialize();
      if (!account.isLoggedInSync) return '/login';
      return null;
    },
    routes: [
      // Корневой маршрут - перенаправляет на splash
      GoRoute(
        path: '/',
        redirect: (context, state) => '/splash',
      ),

      // Стартовый экран (проверка авторизации)
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),

      // Экран входа
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),

      // Регистрация компании
      GoRoute(
        path: '/register-company',
        builder: (context, state) => const CompanyRegistrationScreen(),
      ),
      // Регистрация владельца (extra: Establishment)
      GoRoute(
        path: '/register-owner',
        builder: (context, state) {
          final establishment = state.extra as Establishment?;
          if (establishment == null) {
            return const _RedirectToLogin();
          }
          return OwnerRegistrationScreen(establishment: establishment);
        },
      ),
      // Регистрация сотрудника
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),

      // Главный экран
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),

      // Профиль
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      // Настройки (без данных профиля)
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),

      GoRoute(
        path: '/schedule',
        builder: (context, state) => const ScheduleScreen(),
      ),
      GoRoute(
        path: '/employees',
        builder: (context, state) => const EmployeesScreen(),
      ),
      GoRoute(
        path: '/shift-confirmation',
        builder: (context, state) => const ShiftConfirmationScreen(),
      ),
      GoRoute(
        path: '/inventory',
        builder: (context, state) => const InventoryScreen(),
      ),
      GoRoute(
        path: '/inventory-pf',
        builder: (context, state) => const InventoryScreen(),
      ),
      GoRoute(
        path: '/inventory-received',
        builder: (context, state) => const InventoryReceivedScreen(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: '/expenses',
        builder: (context, state) => const ExpensesPlaceholderScreen(),
      ),
      GoRoute(
        path: '/department/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? 'kitchen';
          return DepartmentPlaceholderScreen(department: id);
        },
      ),

      GoRoute(
        path: '/products',
        builder: (context, state) => const ProductsScreen(),
      ),
      GoRoute(
        path: '/nomenclature',
        builder: (context, state) => const NomenclatureScreen(),
      ),
      GoRoute(
        path: '/products/upload',
        builder: (context, state) {
          print('=== Building ProductUploadScreen route ===');
          try {
            return const ProductUploadScreen();
          } catch (e) {
            print('=== Error building ProductUploadScreen: $e ===');
            return Scaffold(
              appBar: AppBar(title: const Text('Ошибка')),
              body: Center(
                child: Text('Ошибка загрузки экрана: $e'),
              ),
            );
          }
        },
      ),

      GoRoute(
        path: '/product-order',
        builder: (context, state) => const OrderListsScreen(),
      ),
      GoRoute(
        path: '/product-order/new',
        builder: (context, state) => const OrderListCreateScreen(),
      ),
      GoRoute(
        path: '/product-order/new/products',
        builder: (context, state) {
          final draft = state.extra as OrderList?;
          if (draft == null) return const _RedirectToProductOrder();
          return OrderListProductsScreen(draft: draft);
        },
      ),
      GoRoute(
        path: '/product-order/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return OrderListDetailScreen(listId: id);
        },
      ),

      GoRoute(
        path: '/checklists',
        builder: (context, state) => const ChecklistsScreen(),
      ),
      GoRoute(
        path: '/checklists/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return ChecklistEditScreen(checklistId: id);
        },
      ),

      GoRoute(
        path: '/tech-cards',
        builder: (context, state) => const TechCardsListScreen(),
      ),
      GoRoute(
        path: '/tech-cards/new',
        builder: (context, state) {
          final initialFromAi = state.extra as TechCardRecognitionResult?;
          return TechCardEditScreen(techCardId: 'new', initialFromAi: initialFromAi);
        },
      ),
      GoRoute(
        path: '/tech-cards/import-review',
        builder: (context, state) {
          final list = state.extra as List?;
          final cards = list != null ? list.map((e) => e as TechCardRecognitionResult).toList() : <TechCardRecognitionResult>[];
          return TechCardsImportReviewScreen(cards: cards);
        },
      ),
      GoRoute(
        path: '/tech-cards/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return TechCardEditScreen(techCardId: id);
        },
      ),

      // Тест Supabase
      GoRoute(
        path: '/supabase-test',
        builder: (context, state) => const SupabaseTestScreen(),
      ),
    ],
  );
}

/// Стартовый экран для проверки авторизации
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _runSequence();
  }

  Future<void> _runSequence() async {
    // Сначала только логотип на пустом экране
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    await _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    // Убираем ручное перенаправление - оно должно происходить через redirect функцию GoRouter
    final accountManager = context.read<AccountManagerSupabase>();
    await accountManager.initialize();
    if (!mounted) return;

    // Даем время на инициализацию и позволяем GoRouter redirect обработать маршрутизацию
    await Future.delayed(const Duration(milliseconds: 100));
    if (!mounted) return;

    // Принудительно вызываем refresh маршрутизации
    if (accountManager.isLoggedInSync) {
      context.go('/home');
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Image.asset(
          'assets/images/logo.png',
          fit: BoxFit.contain,
          width: 160,
          height: 160,
        ),
      ),
    );
  }
}

class _RedirectToLogin extends StatefulWidget {
  const _RedirectToLogin();

  @override
  State<_RedirectToLogin> createState() => _RedirectToLoginState();
}

class _RedirectToLoginState extends State<_RedirectToLogin> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/login');
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _RedirectToProductOrder extends StatefulWidget {
  const _RedirectToProductOrder();

  @override
  State<_RedirectToProductOrder> createState() => _RedirectToProductOrderState();
}

class _RedirectToProductOrderState extends State<_RedirectToProductOrder> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/product-order');
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}