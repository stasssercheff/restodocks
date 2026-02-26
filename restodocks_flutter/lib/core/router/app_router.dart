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

/// Страница с анимацией: при push — вход справа, при pop — уход вправо (эффект возврата).
CustomTransitionPage<void> _slideTransitionPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: animation.drive(
          Tween<Offset>(
            begin: const Offset(1.0, 0),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        ),
        child: child,
      );
    },
  );
}

/// Настройка маршрутизации приложения
class AppRouter {
  static bool _webLocationCorrected = false;

  static final GoRouter router = GoRouter(
    initialLocation: _getInitialLocation(),
    redirect: (context, state) async {
      final loc = state.matchedLocation;
      // Web: если роутер показал корень/splash — восстанавливаем исходный путь (F5, getCurrentBrowserPath уже /splash)
      if (kIsWeb && (loc == '/' || loc == '/splash')) {
        final target = initial_loc.getCachedInitialPath() ?? initial_loc.getCurrentBrowserPath();
        if (kDebugMode) debugPrint('[Restodocks] redirect: loc=$loc, target=$target');
        if (target != null && target != '/' && target != '/splash' && target.isNotEmpty) return target;
      }
      if (_isPublicPath(loc)) {
        // Web: сохраняем путь для F5 fallback (sessionStorage)
        if (kIsWeb && loc.isNotEmpty && loc != '/' && loc != '/splash') {
          initial_loc.savePathForRefresh(loc);
        }
        return null;
      }
      // Сессия восстановлена в main() — при F5 остаёмся на текущем URL
      final account = context.read<AccountManagerSupabase>();
      if (!account.isLoggedInSync) await account.initialize();
      if (!account.isLoggedInSync) {
        // Сохраняем URL для возврата после входа
        final redirect = loc.isNotEmpty && loc != '/' ? Uri.encodeComponent(loc) : null;
        return redirect != null ? '/login?redirect=$redirect' : '/login';
      }
      // Web: сохраняем путь для F5 fallback
      if (kIsWeb && loc.isNotEmpty && loc != '/' && loc != '/splash') {
        initial_loc.savePathForRefresh(loc);
      }
      return null;
    },
    routes: [
      // Корневой маршрут - при F5 на внутренней странице сохраняем URL, иначе — splash
      GoRoute(
        path: '/',
        redirect: (context, state) {
          if (kIsWeb) {
            // Берём исходный путь до redirect (getCurrentBrowserPath уже может быть /splash)
            final target = initial_loc.getCachedInitialPath() ?? initial_loc.getCurrentBrowserPath();
            if (target != null && target != '/' && target != '/splash' && target.isNotEmpty) return target;
          }
          return '/splash';
        },
      ),

      // Стартовый экран (проверка авторизации)
      GoRoute(
        path: '/splash',
        pageBuilder: (context, state) => _slideTransitionPage(state, const SplashScreen()),
      ),

      // Экран входа (redirect — URL для возврата после входа при F5)
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) {
          final redirect = state.queryParameters['redirect'];
          return _slideTransitionPage(state, LoginScreen(redirectAfterLogin: redirect));
        },
      ),

      // Регистрация компании
      GoRoute(
        path: '/register-company',
        pageBuilder: (context, state) => _slideTransitionPage(state, const CompanyRegistrationScreen()),
      ),
      // Регистрация владельца (extra: Establishment)
      GoRoute(
        path: '/register-owner',
        pageBuilder: (context, state) {
          final establishment = state.extra as Establishment?;
          if (establishment == null) {
            return _slideTransitionPage(state, const _RedirectToLogin());
          }
          return _slideTransitionPage(state, OwnerRegistrationScreen(establishment: establishment));
        },
      ),
      // Регистрация сотрудника
      GoRoute(
        path: '/register',
        pageBuilder: (context, state) => _slideTransitionPage(state, const RegisterScreen()),
      ),
      // Восстановление доступа
      GoRoute(
        path: '/forgot-password',
        pageBuilder: (context, state) => _slideTransitionPage(state, const ForgotPasswordScreen()),
      ),
      GoRoute(
        path: '/reset-password',
        pageBuilder: (context, state) {
          final token = state.queryParameters['token'];
          return _slideTransitionPage(state, ResetPasswordScreen(token: token));
        },
      ),
      // Подтверждение email после регистрации (переход по ссылке вернёт в приложение с сессией)
      GoRoute(
        path: '/confirm-email',
        pageBuilder: (context, state) {
          final email = state.queryParameters['email'] ?? '';
          return _slideTransitionPage(state, ConfirmEmailScreen(email: email));
        },
      ),

      // Главный экран (tab=0 — вкладка «Домой», для перехода из Профиля/Настроек)
      GoRoute(
        path: '/home',
        pageBuilder: (context, state) {
          final tabParam = state.queryParameters['tab'];
          final tab = (tabParam != null && int.tryParse(tabParam) != null)
              ? int.parse(tabParam).clamp(0, 2)
              : null;
          return _slideTransitionPage(state, HomeScreen(initialTabIndex: tab));
        },
      ),

      // Профиль
      GoRoute(
        path: '/profile',
        pageBuilder: (context, state) => _slideTransitionPage(state, const ProfileScreen()),
      ),
      // Настройки (без данных профиля)
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => _slideTransitionPage(state, const SettingsScreen()),
      ),

      GoRoute(
        path: '/schedule',
        pageBuilder: (context, state) {
          final personal = state.queryParameters['personal'] == '1';
          return _slideTransitionPage(state, ScheduleScreen(personalOnly: personal));
        },
      ),
      GoRoute(
        path: '/schedule/:department',
        pageBuilder: (context, state) {
          final department = state.pathParameters['department'] ?? 'all';
          final personal = state.queryParameters['personal'] == '1';
          return _slideTransitionPage(state, ScheduleScreen(department: department, personalOnly: personal));
        },
      ),
      GoRoute(
        path: '/inbox',
        pageBuilder: (context, state) => _slideTransitionPage(state, const InboxScreen()),
        routes: [
          GoRoute(
            path: 'inventory/:id',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return _slideTransitionPage(state, InventoryInboxDetailScreen(documentId: id));
            },
          ),
          GoRoute(
            path: 'order/:id',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return _slideTransitionPage(state, OrderInboxDetailScreen(documentId: id));
            },
          ),
          GoRoute(
            path: 'checklist/:id',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return _slideTransitionPage(state, ChecklistInboxDetailScreen(documentId: id));
            },
          ),
        ],
      ),
      GoRoute(
        path: '/employees',
        pageBuilder: (context, state) => _slideTransitionPage(state, const EmployeesScreen()),
      ),
      GoRoute(
        path: '/shift-confirmation',
        pageBuilder: (context, state) => _slideTransitionPage(state, const ShiftConfirmationScreen()),
      ),
      GoRoute(
        path: '/inventory',
        pageBuilder: (context, state) => _slideTransitionPage(state, const InventoryScreen()),
      ),
      GoRoute(
        path: '/inventory-pf',
        pageBuilder: (context, state) => _slideTransitionPage(state, const InventoryScreen()),
      ),
      GoRoute(
        path: '/inventory-received',
        pageBuilder: (context, state) => _slideTransitionPage(state, const InventoryReceivedScreen()),
      ),
      GoRoute(
        path: '/notifications',
        pageBuilder: (context, state) => _slideTransitionPage(state, const InboxScreen()),
      ),
      GoRoute(
        path: '/expenses',
        pageBuilder: (context, state) => _slideTransitionPage(state, const ExpensesPlaceholderScreen()),
      ),
      GoRoute(
        path: '/expenses/salary',
        pageBuilder: (context, state) => _slideTransitionPage(state, const SalaryExpenseScreen()),
      ),
      GoRoute(
        path: '/department/:id',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? 'kitchen';
          return _slideTransitionPage(state, DepartmentPlaceholderScreen(department: id));
        },
      ),

      GoRoute(
        path: '/products',
        pageBuilder: (context, state) => _slideTransitionPage(state, const ProductsScreen()),
      ),
      GoRoute(
        path: '/menu/:department',
        pageBuilder: (context, state) {
          final department = state.pathParameters['department'] ?? 'kitchen';
          return _slideTransitionPage(state, MenuScreen(department: department));
        },
      ),
      GoRoute(
        path: '/nomenclature',
        pageBuilder: (context, state) {
          final refresh = state.queryParameters['refresh'] == '1';
          return _slideTransitionPage(
            state,
            NomenclatureScreen(key: refresh ? ValueKey('nom_refresh_${DateTime.now().millisecondsSinceEpoch}') : null),
          );
        },
      ),
      GoRoute(
        path: '/nomenclature/:department',
        pageBuilder: (context, state) {
          final department = state.pathParameters['department'] ?? 'general';
          return _slideTransitionPage(state, NomenclatureScreen(department: department));
        },
      ),
      GoRoute(
        path: '/products/upload',
        pageBuilder: (context, state) {
          final addToNom = state.queryParameters['addToNomenclature'];
          final defaultAddToNomenclature = addToNom != 'false';
          try {
            return _slideTransitionPage(state, ProductUploadScreen(defaultAddToNomenclature: defaultAddToNomenclature));
          } catch (e) {
            print('=== Error building ProductUploadScreen: $e ===');
            return _slideTransitionPage(state, Scaffold(
              appBar: AppBar(title: const Text('Ошибка')),
              body: Center(
                child: Text('Ошибка загрузки экрана: $e'),
              ),
            ));
          }
        },
      ),
      GoRoute(
        path: '/import-review',
        pageBuilder: (context, state) {
          final items = state.extra as List<ModerationItem>?;
          if (items == null || items.isEmpty) {
            return _slideTransitionPage(state, const _RedirectToNomenclature());
          }
          return _slideTransitionPage(state, ImportReviewScreen(items: items));
        },
      ),

      GoRoute(
        path: '/product-order',
        pageBuilder: (context, state) => _slideTransitionPage(state, const OrderListsScreen()),
      ),
      GoRoute(
        path: '/product-order-received',
        pageBuilder: (context, state) => _slideTransitionPage(state, const ProductOrderReceivedScreen()),
      ),
      GoRoute(
        path: '/product-order/new',
        pageBuilder: (context, state) => _slideTransitionPage(state, const OrderListCreateScreen()),
      ),
      GoRoute(
        path: '/product-order/new/products',
        pageBuilder: (context, state) {
          final draft = state.extra as OrderList?;
          if (draft == null) return _slideTransitionPage(state, const _RedirectToProductOrder());
          return _slideTransitionPage(state, OrderListProductsScreen(draft: draft));
        },
      ),
      GoRoute(
        path: '/product-order/:id',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return _slideTransitionPage(state, OrderListDetailScreen(listId: id));
        },
      ),

      GoRoute(
        path: '/checklists',
        pageBuilder: (context, state) => _slideTransitionPage(state, const ChecklistsScreen()),
      ),
      GoRoute(
        path: '/checklists/:id',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return _slideTransitionPage(state, ChecklistEditScreen(checklistId: id));
        },
      ),
      GoRoute(
        path: '/checklists/:id/fill',
        pageBuilder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return _slideTransitionPage(state, ChecklistFillScreen(checklistId: id));
        },
      ),

      GoRoute(
        path: '/tech-cards',
        pageBuilder: (context, state) => _slideTransitionPage(state, const TechCardsListScreen()),
      ),
      // /tech-cards/new и /tech-cards/import-review должны быть ДО /tech-cards/:department,
      // иначе /tech-cards/new матчится как department='new' и показывается список вместо формы создания
      GoRoute(
        path: '/tech-cards/new',
        pageBuilder: (context, state) {
          final initialFromAi = state.extra as TechCardRecognitionResult?;
          return _slideTransitionPage(state, TechCardEditScreen(techCardId: 'new', initialFromAi: initialFromAi));
        },
      ),
      GoRoute(
        path: '/tech-cards/import-review',
        pageBuilder: (context, state) {
          final list = state.extra as List?;
          final cards = list != null ? list.map((e) => e as TechCardRecognitionResult).toList() : <TechCardRecognitionResult>[];
          return _slideTransitionPage(state, TechCardsImportReviewScreen(cards: cards));
        },
      ),
      // Маршрут :id должен быть до :department, иначе uuid открывается как «список с department=uuid».
      // По одному сегменту различаем: если это известный цех — список по цеху, иначе — редактирование ТТК по id.
      GoRoute(
        path: '/tech-cards/:segment',
        pageBuilder: (context, state) {
          final segment = state.pathParameters['segment'] ?? '';
          const knownDepartments = ['kitchen', 'bar', 'dining_room'];
          if (knownDepartments.contains(segment)) {
            return _slideTransitionPage(state, TechCardsListScreen(department: segment));
          }
          final viewOnly = state.queryParameters['view'] == '1';
          return _slideTransitionPage(state, TechCardEditScreen(techCardId: segment, forceViewMode: viewOnly));
        },
      ),

      // Тест Supabase
      GoRoute(
        path: '/supabase-test',
        pageBuilder: (context, state) => _slideTransitionPage(state, const SupabaseTestScreen()),
      ),

      // Регистрация соучредителя после принятия приглашения
      GoRoute(
        path: '/register-co-owner',
        pageBuilder: (context, state) {
          final token = state.queryParameters['token'];
          if (token == null || token.isEmpty) {
            return _slideTransitionPage(state, const Scaffold(body: Center(child: Text('Invalid link'))));
          }
          return _slideTransitionPage(state, RegisterCoOwnerScreen(token: token));
        },
      ),
      // Принятие приглашения соучредителем
      GoRoute(
        path: '/accept-co-owner-invitation',
        pageBuilder: (context, state) {
          final token = state.queryParameters['token'];
          if (token == null || token.isEmpty) {
            return _slideTransitionPage(state, const Scaffold(
              body: Center(child: Text('Invalid invitation link')),
            ));
          }
          return _slideTransitionPage(state, AcceptCoOwnerInvitationScreen(token: token));
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
    // Короткая задержка для отображения логотипа
    await Future.delayed(const Duration(milliseconds: 300));
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
      // Web: при F5 — исходный путь из URL (getCurrentBrowserPath уже /splash после redirect)
      final target = kIsWeb
          ? (initial_loc.getCachedInitialPath() ?? initial_loc.getCurrentBrowserPath())
          : null;
      context.go((target != null && target != '/' && target != '/splash' && target.isNotEmpty) ? target : '/home');
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
    final target = initial_loc.getCachedInitialPath() ?? initial_loc.getCurrentBrowserPath();
    if (target == null || target == '/' || target == '/splash') return;
    try {
      final state = GoRouterState.of(context);
      final loc = state.matchedLocation;
      if (loc == '/' || loc == '/splash') {
        AppRouter._webLocationCorrected = true;
        if (mounted) context.go(target);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => widget.child ?? const SizedBox.shrink();
}