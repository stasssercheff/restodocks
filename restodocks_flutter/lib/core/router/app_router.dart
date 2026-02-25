import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../initial_location_stub.dart'
    if (dart.library.html) '../initial_location_web.dart' as initial_loc;
import '../../models/models.dart';
import '../../screens/screens.dart';
import '../../screens/company_registration_screen.dart';
import '../../screens/owner_registration_screen.dart';
import '../../screens/home/schedule_screen.dart';
import '../../screens/home/inbox_screen.dart';
import '../../screens/inventory_inbox_detail_screen.dart';
import '../../screens/order_inbox_detail_screen.dart';
import '../../screens/checklist_inbox_detail_screen.dart';
import '../../screens/home/expenses_placeholder_screen.dart';
import '../../screens/home/department_placeholder_screen.dart';
import '../../screens/supabase_test_screen.dart';
import '../../screens/checklists_screen.dart';
import '../../screens/checklist_edit_screen.dart';
import '../../screens/checklist_fill_screen.dart';
import '../../screens/tech_cards_list_screen.dart';
import '../../screens/tech_card_edit_screen.dart';
import '../../screens/order_lists_screen.dart';
import '../../screens/order_list_create_screen.dart';
import '../../screens/order_list_products_screen.dart';
import '../../screens/order_list_detail_screen.dart';
import '../../screens/accept_co_owner_invitation_screen.dart';
import '../../screens/register_co_owner_screen.dart';
import '../../screens/confirm_email_screen.dart';
import '../../models/order_list.dart';
import '../../services/ai_service.dart';
import '../../services/services.dart';

/// Публичные пути (без проверки авторизации). Не использовать startsWith('/') — иначе все пути считаются публичными.
bool _isPublicPath(String loc) {
  if (loc == '/' || loc == '/splash') return true;
  if (loc.startsWith('/login') || loc.startsWith('/register') || loc.startsWith('/register-co-owner') ||
      loc.startsWith('/forgot-password') || loc.startsWith('/reset-password') ||
      loc.startsWith('/accept-co-owner-invitation') || loc.startsWith('/confirm-email')) return true;
  return false;
}

/// Начальный путь: при F5 (web) — текущая страница из URL, без сброса на домашний
String _getInitialLocation() {
  if (kIsWeb) {
    final loc = initial_loc.getInitialLocation();
    if (loc.isNotEmpty && loc != '/') return loc;
    try {
      final uri = Uri.base;
      if (uri.path.isNotEmpty && uri.path != '/') {
        return uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
      }
    } catch (_) {}
  }
  return '/';
}

/// Настройка маршрутизации приложения
class AppRouter {
  static bool _webLocationCorrected = false;

  static final GoRouter router = GoRouter(
    initialLocation: _getInitialLocation(),
    redirect: (context, state) async {
      final loc = state.matchedLocation;
      // Web: если роутер показал корень/splash, но в адресной строке другой путь — восстанавливаем его (F5)
      if (kIsWeb && (loc == '/' || loc == '/splash')) {
        final browserPath = initial_loc.getCurrentBrowserPath();
        if (kDebugMode) debugPrint('[Restodocks] redirect: loc=$loc, browserPath=$browserPath');
        if (browserPath != null) return browserPath;
      }
      if (_isPublicPath(loc)) return null;
      // Сессия восстановлена в main() — при F5 остаёмся на текущем URL
      final account = context.read<AccountManagerSupabase>();
      if (!account.isLoggedInSync) await account.initialize();
      if (!account.isLoggedInSync) {
        // Сохраняем URL для возврата после входа
        final redirect = loc.isNotEmpty && loc != '/' ? Uri.encodeComponent(loc) : null;
        return redirect != null ? '/login?redirect=$redirect' : '/login';
      }
      return null;
    },
    routes: [
      // Корневой маршрут - при F5 на внутренней странице сохраняем URL, иначе — splash
      GoRoute(
        path: '/',
        redirect: (context, state) {
          if (kIsWeb) {
            final bp = initial_loc.getCurrentBrowserPath();
            if (bp != null && bp != '/splash') return bp;
          }
          return '/splash';
        },
      ),

      // Стартовый экран (проверка авторизации)
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),

      // Экран входа (redirect — URL для возврата после входа при F5)
      GoRoute(
        path: '/login',
        builder: (context, state) {
          final redirect = state.queryParameters['redirect'];
          return LoginScreen(redirectAfterLogin: redirect);
        },
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
      // Восстановление доступа
      GoRoute(
        path: '/forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) {
          final token = state.queryParameters['token'];
          return ResetPasswordScreen(token: token);
        },
      ),
      // Подтверждение email после регистрации (переход по ссылке вернёт в приложение с сессией)
      GoRoute(
        path: '/confirm-email',
        builder: (context, state) {
          final email = state.queryParameters['email'] ?? '';
          return ConfirmEmailScreen(email: email);
        },
      ),

      // Главный экран (tab=0 — вкладка «Домой», для перехода из Профиля/Настроек)
      GoRoute(
        path: '/home',
        builder: (context, state) {
          final tabParam = state.queryParameters['tab'];
          final tab = (tabParam != null && int.tryParse(tabParam) != null)
              ? int.parse(tabParam).clamp(0, 2)
              : null;
          return HomeScreen(initialTabIndex: tab);
        },
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
        builder: (context, state) {
          final personal = state.queryParameters['personal'] == '1';
          return ScheduleScreen(personalOnly: personal);
        },
      ),
      GoRoute(
        path: '/schedule/:department',
        builder: (context, state) {
          final department = state.pathParameters['department'] ?? 'all';
          final personal = state.queryParameters['personal'] == '1';
          return ScheduleScreen(department: department, personalOnly: personal);
        },
      ),
      GoRoute(
        path: '/inbox',
        builder: (context, state) => const InboxScreen(),
        routes: [
          GoRoute(
            path: 'inventory/:id',
            builder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return InventoryInboxDetailScreen(documentId: id);
            },
          ),
          GoRoute(
            path: 'order/:id',
            builder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return OrderInboxDetailScreen(documentId: id);
            },
          ),
          GoRoute(
            path: 'checklist/:id',
            builder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return ChecklistInboxDetailScreen(documentId: id);
            },
          ),
        ],
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
        builder: (context, state) => const InboxScreen(),
      ),
      GoRoute(
        path: '/expenses',
        builder: (context, state) => const ExpensesPlaceholderScreen(),
      ),
      GoRoute(
        path: '/expenses/salary',
        builder: (context, state) => const SalaryExpenseScreen(),
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
        path: '/menu/:department',
        builder: (context, state) {
          final department = state.pathParameters['department'] ?? 'kitchen';
          return MenuScreen(department: department);
        },
      ),
      GoRoute(
        path: '/nomenclature',
        builder: (context, state) {
          return const NomenclatureScreen();
        },
      ),
      GoRoute(
        path: '/nomenclature/:department',
        builder: (context, state) {
          final department = state.pathParameters['department'] ?? 'general';
          return NomenclatureScreen(department: department);
        },
      ),
      GoRoute(
        path: '/products/upload',
        builder: (context, state) {
          final addToNom = state.queryParameters['addToNomenclature'];
          final defaultAddToNomenclature = addToNom != 'false';
          try {
            return ProductUploadScreen(defaultAddToNomenclature: defaultAddToNomenclature);
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
        path: '/import-review',
        builder: (context, state) {
          final items = state.extra as List<ModerationItem>?;
          if (items == null || items.isEmpty) {
            return const _RedirectToNomenclature();
          }
          return ImportReviewScreen(items: items);
        },
      ),

      GoRoute(
        path: '/product-order',
        builder: (context, state) => const OrderListsScreen(),
      ),
      GoRoute(
        path: '/product-order-received',
        builder: (context, state) => const ProductOrderReceivedScreen(),
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
        path: '/checklists/:id/fill',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return ChecklistFillScreen(checklistId: id);
        },
      ),

      GoRoute(
        path: '/tech-cards',
        builder: (context, state) => const TechCardsListScreen(),
      ),
      // /tech-cards/new и /tech-cards/import-review должны быть ДО /tech-cards/:department,
      // иначе /tech-cards/new матчится как department='new' и показывается список вместо формы создания
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
      // Маршрут :id должен быть до :department, иначе uuid открывается как «список с department=uuid».
      // По одному сегменту различаем: если это известный цех — список по цеху, иначе — редактирование ТТК по id.
      GoRoute(
        path: '/tech-cards/:segment',
        builder: (context, state) {
          final segment = state.pathParameters['segment'] ?? '';
          const knownDepartments = ['kitchen', 'bar', 'dining_room'];
          if (knownDepartments.contains(segment)) {
            return TechCardsListScreen(department: segment);
          }
          final viewOnly = state.queryParameters['view'] == '1';
          return TechCardEditScreen(techCardId: segment, forceViewMode: viewOnly);
        },
      ),

      // Тест Supabase
      GoRoute(
        path: '/supabase-test',
        builder: (context, state) => const SupabaseTestScreen(),
      ),

      // Регистрация соучредителя после принятия приглашения
      GoRoute(
        path: '/register-co-owner',
        builder: (context, state) {
          final token = state.queryParameters['token'];
          if (token == null || token.isEmpty) {
            return const Scaffold(body: Center(child: Text('Invalid link')));
          }
          return RegisterCoOwnerScreen(token: token);
        },
      ),
      // Принятие приглашения соучредителем
      GoRoute(
        path: '/accept-co-owner-invitation',
        builder: (context, state) {
          final token = state.queryParameters['token'];
          if (token == null || token.isEmpty) {
            return const Scaffold(
              body: Center(child: Text('Invalid invitation link')),
            );
          }
          return AcceptCoOwnerInvitationScreen(token: token);
        },
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
      // Web: при F5 мог оказаться splash при глубокой ссылке — идём по URL из адресной строки
      final bp = kIsWeb ? initial_loc.getCurrentBrowserPath() : null;
      final target = (bp != null && bp != '/splash') ? bp : '/home';
      context.go(target);
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

class _RedirectToNomenclature extends StatefulWidget {
  const _RedirectToNomenclature();

  @override
  State<_RedirectToNomenclature> createState() => _RedirectToNomenclatureState();
}

class _RedirectToNomenclatureState extends State<_RedirectToNomenclature> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go('/nomenclature');
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

/// Обёртка для web: после первого кадра синхронизирует маршрут с адресной строкой (F5).
class WebLocationCorrection extends StatefulWidget {
  const WebLocationCorrection({super.key, required this.child});
  final Widget? child;

  @override
  State<WebLocationCorrection> createState() => _WebLocationCorrectionState();
}

class _WebLocationCorrectionState extends State<WebLocationCorrection> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _correctOnce());
  }

  void _correctOnce() {
    if (!mounted || !kIsWeb || AppRouter._webLocationCorrected) return;
    final browserPath = initial_loc.getCurrentBrowserPath();
    if (browserPath == null) return;
    try {
      final state = GoRouterState.of(context);
      final loc = state.matchedLocation;
      if (loc == '/' || loc == '/splash') {
        AppRouter._webLocationCorrected = true;
        if (mounted) context.go(browserPath);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => widget.child ?? const SizedBox.shrink();
}