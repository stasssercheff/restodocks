import 'package:flutter/foundation.dart';
import '../../utils/dev_log.dart';
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
import '../../screens/inventory_screen.dart';
import '../../screens/order_inbox_detail_screen.dart';
import '../../screens/checklist_inbox_detail_screen.dart';
import '../../screens/iiko_inventory_inbox_detail_screen.dart';
import '../../screens/inventory_merge_screen.dart';
import '../../screens/writeoff_inbox_detail_screen.dart';
import '../../screens/writeoff_summary_inbox_screen.dart';
import '../../screens/writeoffs_screen.dart';
import '../../screens/haccp_log_detail_screen.dart';
import '../../screens/home/expenses_screen.dart';
import '../../screens/home/department_placeholder_screen.dart';
import '../../screens/supabase_test_screen.dart';
import '../../screens/checklist_edit_screen.dart';
import '../../screens/checklist_fill_screen.dart';
import '../../screens/tech_cards_list_screen.dart';
import '../../screens/tech_card_edit_screen.dart';
import '../../screens/order_lists_screen.dart';
import '../../screens/order_list_create_screen.dart';
import '../../screens/order_list_products_screen.dart';
import '../../screens/order_list_detail_screen.dart';
import '../../screens/order_create_screen.dart';
import '../../screens/accept_co_owner_invitation_screen.dart';
import '../../screens/register_co_owner_screen.dart';
import '../../screens/add_establishment_screen.dart';
import '../../screens/auth_confirm_click_screen.dart';
import '../../screens/auth_confirm_screen.dart';
import '../../screens/confirm_email_screen.dart';
import '../../screens/admin_screen.dart';
import '../../models/order_list.dart';
import '../../services/ai_service.dart';
import '../../services/services.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/inbox_notification_listener.dart';

/// Emails владельцев платформы — единственные кто видит /admin
const _platformAdminEmails = <String>{
  'stasssercheff@gmail.com', // замени на свой email
};

bool _isPlatformAdmin(String email) => _platformAdminEmails.contains(email.toLowerCase().trim());

/// Публичные пути (без проверки авторизации). Не использовать startsWith('/') — иначе все пути считаются публичными.
bool _isPublicPath(String loc) {
  if (loc == '/' || loc == '/splash') return true;
  if (loc.startsWith('/login') || loc.startsWith('/register') || loc.startsWith('/register-co-owner') ||
      loc.startsWith('/forgot-password') || loc.startsWith('/reset-password') ||
      loc.startsWith('/accept-co-owner-invitation') || loc.startsWith('/confirm-email') ||
      loc.startsWith('/auth/confirm')) return true;
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

/// Страница с анимацией.
/// Если в state.extra передан {'back': true} — анимация обратная (экран уходит вправо),
/// имитируя нажатие «назад». Иначе — стандартная MaterialPage (Cupertino, слева направо).
Page<void> _slideTransitionPage(GoRouterState state, Widget child) {
  final isBack = (state.extra is Map) && (state.extra as Map)['back'] == true;
  if (!isBack) {
    return MaterialPage<void>(key: state.pageKey, child: child);
  }
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      // Новый экран (возврат «назад»): приходит слева, уходит влево
      final slideIn = Tween<Offset>(
        begin: const Offset(-1.0, 0.0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeInOut));
      // Текущий экран уходит вправо (как при pop)
      final slideOut = Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(1.0, 0.0),
      ).animate(CurvedAnimation(parent: secondaryAnimation, curve: Curves.easeInOut));
      return SlideTransition(
        position: slideOut,
        child: SlideTransition(position: slideIn, child: child),
      );
    },
  );
}

/// Настройка маршрутизации приложения
class AppRouter {
  static bool _webLocationCorrected = false;

  /// Key for root navigator — used by AppToastService to insert overlay.
  static final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

  static final GoRouter router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: _getInitialLocation(),
    redirect: (context, state) async {
      // Web: Uri.base — фактический URL страницы (при переходе по ссылке из письма)
      if (kIsWeb && Uri.base.path.startsWith('/auth/confirm')) {
        return null;
      }
      final loc = state.matchedLocation;
      final path = Uri.tryParse(loc.startsWith('/') ? loc : '/$loc')?.path ?? loc.split('?').first;
      if (path.startsWith('/auth/confirm')) {
        if (kIsWeb && path.isNotEmpty) initial_loc.savePathForRefresh(loc);
        return null;
      }
      // Web: если роутер показал корень/splash — восстанавливаем исходный путь
      if (kIsWeb && (loc == '/' || loc == '/splash')) {
        final target = initial_loc.getCachedInitialPath() ?? initial_loc.getCurrentBrowserPath();
        if (kDebugMode) devLog('[Restodocks] redirect: loc=$loc, target=$target');
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
        // Сохраняем полный URL (path + query) для возврата после входа — иначе теряются token_hash и type для auth/confirm
        final fullLoc = state.location; // location включает path и query
        final redirect = fullLoc.isNotEmpty && fullLoc != '/' ? Uri.encodeComponent(fullLoc) : null;
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
      // Редирект Supabase после подтверждения email — восстанавливаем сессию и ведём в /home
      GoRoute(
        path: '/auth/confirm',
        pageBuilder: (context, state) => _slideTransitionPage(state, const AuthConfirmScreen()),
      ),
      // Прокладка: ссылка в письме → нажать кнопку → verifyOtp или редирект на Supabase
      GoRoute(
        path: '/auth/confirm-click',
        pageBuilder: (context, state) {
          final r = state.queryParameters['r'] ?? '';
          final tokenHash = state.queryParameters['token_hash'] ?? '';
          final type = state.queryParameters['type'] ?? '';
          return _slideTransitionPage(
            state,
            AuthConfirmClickScreen(redirectParam: r, tokenHash: tokenHash, otpType: type),
          );
        },
      ),

      // Списания — без нижней панели
      GoRoute(
        path: '/writeoffs',
        pageBuilder: (context, state) => _slideTransitionPage(state, const WriteoffsScreen()),
      ),
      // Инвентаризация — без нижней панели
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
        path: '/inventory-iiko',
        pageBuilder: (context, state) => _slideTransitionPage(state, const InventoryIikoScreen()),
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

      // Shell — все рабочие экраны с нижней навигационной панелью
      ShellRoute(
        builder: (context, state, child) => AppShell(
          child: InboxNotificationListener(child: child),
        ),
        routes: [
          // Главный экран
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

          // Личный кабинет (нижняя вкладка)
          GoRoute(
            path: '/personal-cabinet',
            pageBuilder: (context, state) => _slideTransitionPage(state, const PersonalCabinetScreen()),
          ),
          // Профиль (детали)
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) => _slideTransitionPage(state, const ProfileScreen()),
          ),
          // Настройки
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => _slideTransitionPage(state, const SettingsScreen()),
          ),
          // Добавить заведение (владелец)
          GoRoute(
            path: '/add-establishment',
            pageBuilder: (context, state) => _slideTransitionPage(state, const AddEstablishmentScreen()),
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
              GoRoute(
                path: 'iiko/:id',
                pageBuilder: (context, state) {
                  final id = state.pathParameters['id'] ?? '';
                  return _slideTransitionPage(
                      state, IikoInventoryInboxDetailScreen(documentId: id));
                },
              ),
              GoRoute(
                path: 'writeoff/:id',
                pageBuilder: (context, state) {
                  final id = state.pathParameters['id'] ?? '';
                  return _slideTransitionPage(
                      state, WriteoffInboxDetailScreen(documentId: id));
                },
              ),
              GoRoute(
                path: 'writeoff-summary',
                pageBuilder: (context, state) {
                  final extra = state.extra;
                  List<InboxDocument> docs = [];
                  String dateLabel = '';
                  if (extra is Map) {
                    docs = (extra['documents'] as List<dynamic>?)
                            ?.whereType<InboxDocument>()
                            .toList() ??
                        [];
                    dateLabel = (extra['dateLabel'] as String?) ?? '';
                  }
                  return _slideTransitionPage(
                    state,
                    WriteoffSummaryInboxScreen(documents: docs, dateLabel: dateLabel),
                  );
                },
              ),
              GoRoute(
                path: 'chat/:employeeId',
                pageBuilder: (context, state) {
                  final employeeId = state.pathParameters['employeeId'] ?? '';
                  return _slideTransitionPage(state, EmployeeChatScreen(otherEmployeeId: employeeId));
                },
              ),
              GoRoute(
                path: 'group/new',
                pageBuilder: (context, state) {
                  return _slideTransitionPage(state, const CreateGroupChatScreen());
                },
              ),
              GoRoute(
                path: 'group/:roomId',
                pageBuilder: (context, state) {
                  final roomId = state.pathParameters['roomId'] ?? '';
                  return _slideTransitionPage(state, GroupChatScreen(roomId: roomId));
                },
              ),
              GoRoute(
                path: 'merge',
                pageBuilder: (context, state) {
                  final extra = state.extra;
                  List<InboxDocument> typed = [];
                  if (extra is List) {
                    typed = extra
                        .where((e) => e is InboxDocument)
                        .cast<InboxDocument>()
                        .where((d) =>
                            d.type == DocumentType.inventory ||
                            d.type == DocumentType.iikoInventory ||
                            d.type == DocumentType.writeoff)
                        .toList();
                  }
                  return _slideTransitionPage(
                    state,
                    InventoryMergeScreen(documents: typed),
                  );
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
            path: '/notifications',
            pageBuilder: (context, state) {
              final messagesOnly = state.queryParameters['tab'] == 'messages';
              return _slideTransitionPage(
                state,
                InboxScreen(messagesOnly: messagesOnly),
              );
            },
          ),
          GoRoute(
            path: '/expenses',
            pageBuilder: (context, state) => _slideTransitionPage(state, const ExpensesScreen()),
          ),
          GoRoute(
            path: '/expenses/salary',
            pageBuilder: (context, state) {
              final department = state.queryParameters['department']; // kitchen|bar|hall для ФЗП по подразделению
              return _slideTransitionPage(state, SalaryExpenseScreen(departmentFilter: department));
            },
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
              final method = state.queryParameters['method'];
              try {
                return _slideTransitionPage(
                  state,
                  ProductUploadScreen(
                    defaultAddToNomenclature: defaultAddToNomenclature,
                    initialMethod: method,
                  ),
                );
              } catch (e) {
                devLog('=== Error building ProductUploadScreen: $e ===');
                return _slideTransitionPage(state, Scaffold(
                  appBar: AppBar(title: const Text('Ошибка')),
                  body: Center(child: Text('Ошибка загрузки экрана: $e')),
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
            pageBuilder: (context, state) {
              final dept = state.queryParameters['department'] ?? 'kitchen';
              return _slideTransitionPage(state, OrderListsScreen(department: dept));
            },
          ),
          GoRoute(
            path: '/product-order-received',
            pageBuilder: (context, state) => _slideTransitionPage(state, const ProductOrderReceivedScreen()),
          ),
          GoRoute(
            path: '/product-order/new',
            pageBuilder: (context, state) {
              final dept = state.queryParameters['department'] ?? 'kitchen';
              return _slideTransitionPage(state, OrderListCreateScreen(department: dept));
            },
          ),
          GoRoute(
            path: '/product-order/create-order',
            pageBuilder: (context, state) {
              final dept = state.queryParameters['department'] ?? 'kitchen';
              return _slideTransitionPage(state, OrderCreateScreen(department: dept));
            },
          ),
          GoRoute(
            path: '/product-order/new/products',
            pageBuilder: (context, state) {
              final draft = state.extra as OrderList?;
              if (draft == null) return _slideTransitionPage(state, const _RedirectToProductOrder());
              final popCount = int.tryParse(state.queryParameters['pop'] ?? '') ?? 2;
              return _slideTransitionPage(state, OrderListProductsScreen(draft: draft, popCountOnSave: popCount));
            },
          ),
          GoRoute(
            path: '/suppliers/:department',
            pageBuilder: (context, state) {
              final dept = state.pathParameters['department'] ?? 'kitchen';
              return _slideTransitionPage(state, SuppliersScreen(department: dept));
            },
          ),
          GoRoute(
            path: '/product-order/:id',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              final dept = state.queryParameters['department'] ?? 'kitchen';
              return _slideTransitionPage(state, OrderListDetailScreen(listId: id, department: dept));
            },
          ),

          GoRoute(
            path: '/checklists',
            pageBuilder: (context, state) {
              final dept = state.queryParameters['department'] ?? 'kitchen';
              final refresh = state.queryParameters['refresh'] == '1';
              return _slideTransitionPage(
                state,
                ChecklistsScreen(
                  key: refresh ? ValueKey('checklists_refresh_${DateTime.now().millisecondsSinceEpoch}') : null,
                  department: dept,
                ),
              );
            },
          ),
          GoRoute(
            path: '/checklists/:id',
            pageBuilder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              final viewOnly = state.queryParameters['view'] == '1';
              final department = state.queryParameters['department'] ?? 'kitchen';
              return _slideTransitionPage(state, ChecklistEditScreen(checklistId: id, viewOnly: viewOnly, initialDepartment: department));
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
            path: '/documentation',
            pageBuilder: (context, state) => _slideTransitionPage(state, const DocumentationScreen()),
            routes: [
              GoRoute(
                path: 'new',
                pageBuilder: (context, state) => _slideTransitionPage(state, const DocumentationEditScreen(documentId: 'new')),
              ),
              GoRoute(
                path: ':id',
                pageBuilder: (context, state) {
                  final id = state.pathParameters['id'] ?? '';
                  return _slideTransitionPage(state, DocumentationViewScreen(documentId: id));
                },
                routes: [
                  GoRoute(
                    path: 'edit',
                    pageBuilder: (context, state) {
                      final id = state.pathParameters['id'] ?? '';
                      return _slideTransitionPage(state, DocumentationEditScreen(documentId: id));
                    },
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/haccp-journals',
            pageBuilder: (context, state) => _slideTransitionPage(state, const HaccpJournalsScreen()),
            routes: [
              GoRoute(
                path: ':logType',
                pageBuilder: (context, state) {
                  final code = state.pathParameters['logType'] ?? '';
                  return _slideTransitionPage(state, HaccpJournalDetailScreen(logTypeCode: code));
                },
                routes: [
                  GoRoute(
                    path: 'add',
                    pageBuilder: (context, state) {
                      final code = state.pathParameters['logType'] ?? '';
                      return _slideTransitionPage(state, HaccpEntryFormScreen(logTypeCode: code));
                    },
                  ),
                  GoRoute(
                    path: 'view',
                    pageBuilder: (context, state) {
                      final extra = state.extra;
                      if (extra is! Map) return _slideTransitionPage(state, const SizedBox());
                      final log = extra['log'];
                      final employee = extra['employee'];
                      final creator = extra['creator'];
                      final subjectNameSnapshot = extra['subjectNameSnapshot'] as String?;
                      final subjectPositionSnapshot = extra['subjectPositionSnapshot'] as String?;
                      if (log == null) return _slideTransitionPage(state, const SizedBox());
                      return _slideTransitionPage(
                        state,
                        HaccpLogDetailScreen(
                          log: log as HaccpLog,
                          employee: employee as Employee?,
                          creator: creator as Employee?,
                          subjectNameSnapshot: subjectNameSnapshot,
                          subjectPositionSnapshot: subjectPositionSnapshot,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/tech-cards',
            pageBuilder: (context, state) {
              final refresh = state.queryParameters['refresh'] == '1';
              return _slideTransitionPage(
                state,
                TechCardsListScreen(key: refresh ? ValueKey('ttk_refresh_${DateTime.now().millisecondsSinceEpoch}') : null),
              );
            },
          ),
          GoRoute(
            path: '/tech-cards/new',
            pageBuilder: (context, state) {
              TechCardRecognitionResult? initialFromAi;
              String? initialCategory;
              List<String>? initialSections;
              bool? initialIsSemiFinished;
              int? initialTypeRevision;
              String? initialHeaderSignature;
              List<List<String>>? initialSourceRows;
              final extra = state.extra;
              if (extra is Map) {
                initialFromAi = extra['result'] as TechCardRecognitionResult?;
                initialCategory = extra['category'] as String?;
                initialSections = (extra['sections'] as List?)?.cast<String>();
                initialIsSemiFinished = extra['isSemiFinished'] as bool?;
                final rev = extra['typeRevision'];
                initialTypeRevision = rev is num ? rev.toInt() : null;
                initialHeaderSignature = extra['headerSignature'] as String?;
                final raw = extra['sourceRows'];
                initialSourceRows = raw is List && raw.isNotEmpty && raw.first is List
                    ? (raw as List).map((e) => (e as List).map((c) => (c ?? '').toString()).toList()).toList()
                    : null;
              } else if (extra is TechCardRecognitionResult) {
                initialFromAi = extra;
              }
              final department = state.queryParameters['department'];
              // Placeholder сначала — push завершается мгновенно, тяжёлый TechCardEditScreen строим в след. кадре
              return _slideTransitionPage(state, _DeferredTechCardNew(
                initialFromAi: initialFromAi,
                department: department,
                initialCategory: initialCategory,
                initialSections: initialSections,
                initialIsSemiFinished: initialIsSemiFinished,
                initialTypeRevision: initialTypeRevision,
                initialHeaderSignature: initialHeaderSignature,
                initialSourceRows: initialSourceRows,
              ));
            },
          ),
          GoRoute(
            path: '/tech-cards/import-review',
            pageBuilder: (context, state) {
              List<TechCardRecognitionResult> cards;
              String? headerSignature;
              List<List<String>>? sourceRows;
              final extra = state.extra;
              if (extra is Map && extra['cards'] is List) {
                cards = (extra['cards'] as List).map((e) => e as TechCardRecognitionResult).toList();
                headerSignature = extra['headerSignature'] as String?;
                final raw = extra['sourceRows'];
                sourceRows = raw is List && raw.isNotEmpty && raw.first is List
                    ? (raw as List).map((e) => (e as List).map((c) => (c ?? '').toString()).toList()).toList()
                    : null;
              } else if (extra is List) {
                cards = extra.map((e) => e as TechCardRecognitionResult).toList();
              } else {
                cards = [];
              }
              final department = state.queryParameters['department'] ?? 'kitchen';
              return _slideTransitionPage(state, TechCardsImportReviewScreen(cards: cards, headerSignature: headerSignature, sourceRows: sourceRows, department: department));
            },
          ),
          GoRoute(
            path: '/tech-cards/:segment',
            pageBuilder: (context, state) {
              final segment = state.pathParameters['segment'] ?? '';
              const knownDepartments = ['kitchen', 'bar', 'dining_room', 'banquet-catering', 'banquet-catering-bar'];
              if (knownDepartments.contains(segment)) {
                final refresh = state.queryParameters['refresh'] == '1';
                return _slideTransitionPage(
                  state,
                  TechCardsListScreen(
                    key: refresh ? ValueKey('ttk_refresh_${DateTime.now().millisecondsSinceEpoch}') : null,
                    department: segment,
                  ),
                );
              }
              final viewOnly = state.queryParameters['view'] == '1';
              final hallView = state.queryParameters['hall'] == '1';
              return _slideTransitionPage(state, TechCardEditScreen(techCardId: segment, forceViewMode: viewOnly, forceHallView: hallView));
            },
          ),

          // Тест Supabase
          GoRoute(
            path: '/supabase-test',
            pageBuilder: (context, state) => _slideTransitionPage(state, const SupabaseTestScreen()),
          ),

          // Платформенный кабинет администратора
          GoRoute(
            path: '/admin',
            redirect: (context, state) {
              final account = context.read<AccountManagerSupabase>();
              final email = account.currentEmployee?.email ?? '';
              if (!_isPlatformAdmin(email)) return '/home';
              return null;
            },
            pageBuilder: (context, state) => _slideTransitionPage(state, const AdminScreen()),
          ),
        ],
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
    final accountManager = context.read<AccountManagerSupabase>();
    await accountManager.initialize();
    if (!mounted) return;

    if (accountManager.isLoggedInSync) {
      // Web: при F5 — восстанавливаем исходный путь из кэша или localStorage.
      // _cachedInitialPath кэшируется в getInitialLocation() который вызывается
      // в main() до любых redirect, поэтому всегда содержит реальный URL.
      String? target;
      if (kIsWeb) {
        target = initial_loc.getCachedInitialPath();
        // Дополнительный fallback: читаем из localStorage напрямую
        if (target == null || target == '/' || target == '/splash') {
          target = initial_loc.getLastSavedPath();
        }
        // Фильтруем служебные пути
        if (target == '/' || target == '/splash' || target?.isEmpty == true) {
          target = null;
        }
      }
      devLog('[Splash] go → ${target ?? '/home'} (cached=${initial_loc.getCachedInitialPath()})');
      context.go(target ?? '/home');
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SizedBox.expand(
        child: Image.asset(
          'assets/images/welcome_logo.png',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

/// Placeholder для /tech-cards/new: лёгкий Scaffold сначала, TechCardEditScreen строим в след. кадре.
/// Push завершается мгновенно — кнопка «Создать» не зависает.
class _DeferredTechCardNew extends StatefulWidget {
  const _DeferredTechCardNew({
    this.initialFromAi,
    this.department,
    this.initialCategory,
    this.initialSections,
    this.initialIsSemiFinished,
    this.initialTypeRevision,
    this.initialHeaderSignature,
    this.initialSourceRows,
  });
  final TechCardRecognitionResult? initialFromAi;
  final String? department;
  final String? initialCategory;
  final List<String>? initialSections;
  final bool? initialIsSemiFinished;
  final int? initialTypeRevision;
  final String? initialHeaderSignature;
  final List<List<String>>? initialSourceRows;

  @override
  State<_DeferredTechCardNew> createState() => _DeferredTechCardNewState();
}

class _DeferredTechCardNewState extends State<_DeferredTechCardNew> {
  Widget? _child;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _child = TechCardEditScreen(
          techCardId: 'new',
          initialFromAi: widget.initialFromAi,
          department: widget.department,
          initialCategory: widget.initialCategory,
          initialSections: widget.initialSections,
          initialIsSemiFinished: widget.initialIsSemiFinished,
          initialTypeRevision: widget.initialTypeRevision,
          initialHeaderSignature: widget.initialHeaderSignature,
          initialSourceRows: widget.initialSourceRows,
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_child != null) return _child!;
    final loc = context.read<LocalizationService>();
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Text(loc.t('create_tech_card')),
      ),
      body: const Center(child: CircularProgressIndicator()),
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