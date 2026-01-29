# Аудит Restodocks Flutter (январь 2025)

## 1. Критические проблемы

### 1.1 Авторизация и Splash
- **Splash** проверяет `SupabaseService.isAuthenticated` (Supabase Auth).
- **Логин** идёт через `AccountManagerSupabase`: таблица `employees`, свой пароль. Supabase Auth **не используется**.
- Итог: после входа `isAuthenticated` всегда `false` → Splash всегда редиректит на `/login`, даже у залогиненных.
- **Сессия не сохраняется**: `currentEmployee`/`establishment` только в памяти. Обновление страницы (web) → выход.

**Рекомендация:**  
- Проверять на Splash `AccountManagerSupabase.currentEmployee != null` (или `isLoggedIn()`).  
- Сохранять сессию в `SharedPreferences` (например, `employee_id` + `establishment_id`), при старте подгружать из БД и восстанавливать `currentEmployee`/`establishment`.

### 1.2 Навигация: Navigator vs GoRouter
- Приложение использует **GoRouter** (`MaterialApp.router`), но в экранах много **Navigator** (`push`, `pushNamed`, `pushReplacementNamed`).
- Named-маршруты заданы только в GoRouter, не в `MaterialApp`.  
- Итог: `pushReplacementNamed('/home')` и т.п. могут не находить маршруты или вести себя непредсказуемо.

**Использовать везде:** `context.go('/home')`, `context.push('/profile')`, `context.pop()` и т.д. (GoRouter).

### 1.3 Ошибки входа/регистрации не локализованы
- В `LoginScreen`: «Компания с таким PIN не найдена», «Неверный email или пароль» — захардкожены по-русски.
- В `RegisterScreen`: «Ошибка регистрации: ...» — то же.
- Нужны ключи в `localizable.json` и использование `localization.t(...)`.

---

## 2. Важные замечания

### 2.1 Тема
- В `AppTheme` заданы `lightTheme` и `darkTheme`, но в `RestodocksApp` используются только `primaryColor` и `useMaterial3`.
- Тёмная тема и полная тема из `AppTheme` не подключены.

**Рекомендация:** использовать `theme: AppTheme.lightTheme`, `darkTheme: AppTheme.darkTheme`, при необходимости `themeMode`.

### 2.2 Регистрация компании и PIN
- При **новой компании** форма даёт «Сгенерировать PIN» и показывает его в поле.
- `createEstablishment` вызывает `Establishment.create()`, который **внутри снова** генерирует PIN.
- Итог: PIN в форме и PIN в БД могут различаться.

**Рекомендация:** при создании новой компании передавать в `createEstablishment` PIN из формы (или один раз сгенерировать и использовать и в форме, и при создании).

### 2.3 `createEstablishment` и `owner_id`
- `ownerId` передаётся как `_supabase.currentUser?.id ?? ''` (Supabase Auth).
- Supabase Auth не используется → всегда `''`.
- Позже `owner_id` обновляется при создании владельца в `createEmployeeForCompany`. В БД в итоге верно, но изначальная вставка с пустым `owner_id`.

### 2.4 Продукты: `addProduct`
- После `insertData` возвращается созданная запись (с реальным `id` из БД).
- В коде в `_allProducts` добавляется переданный `Product` с локальным `id`.
- Итог: в списке может быть продукт с неверным `id`.

**Рекомендация:** парсить ответ от `insertData`, создавать `Product` из него и добавлять в `_allProducts`.

### 2.5 `canViewDepartment('management')`
- Сейчас только `hasRole('owner')` видит «Управление».
- Роли `manager`, `general_manager`, `assistant_manager` не дают доступа.

**Рекомендация:** добавить проверку этих ролей для `management`.

### 2.6 Секция кухни при регистрации
- `_selectedSection` изначально `null`, при выборе «Кухня» показывается `DropdownButtonFormField` с `value: _selectedSection`.
- Нет пункта «по умолчанию» → при `null` возможна ошибка.

**Рекомендация:** задать значение по умолчанию (например, `'hot_kitchen'`) при `department == 'kitchen'`.

---

## 3. Прочее

### 3.1 Неиспользуемый код
- Импорт `flutter_localizations` в `main.dart` есть, но `localizationsDelegates` / `supportedLocales` не заданы (используется свой `LocalizationService`). Импорт можно убрать, если не планируется использование.
- Старые сервисы `AccountManager`, `ProductStore`, `TechCardService` (без Supabase) экспортируются в `services.dart`, но в приложении не используются. Можно оставить для совместимости или пометить как deprecated и постепенно убрать.

### 3.2 Заглушки и моки
- **KitchenScreen**: статистика (12, 5, 8), список задач — заглушки. Кнопки (ТТК, расписание, инвентарь, отчёты) показывают SnackBar «в разработке».
- Аналогичные заглушки вероятны в Bar, DiningRoom, Management — при дальнейшей разработке их нужно заменить на реальные данные и навигацию.

### 3.3 Безопасность
- Пароли сотрудников хранятся в открытом виде (`password_hash` фактически = пароль). В коде есть TODO про bcrypt.  
- Для продакшена обязательно хеширование паролей на бэкенде ( Supabase Edge Functions или отдельный API).

### 3.4 Локализация
- Выбор языка и сохранение в `LocalizationService` есть, но сохранение в `SharedPreferences` не реализовано (TODO).
- `LocalizationService` не передаётся в `MaterialApp` (`locale`, `supportedLocales` и т.д.), тема/системная локаль не переключаются автоматически.

### 3.5 Деплой и конфиг
- **Vercel**: `vercel.json`, `vercel-build.sh`, `config.json` из env — настроено.
- `assets/config.json` с пустыми `SUPABASE_*` — ок для локальной разработки (берётся из `.env`).

### 3.6 Web
- `index.html`, `manifest.json`, `theme-icons.js`, `_redirects` — на месте.
- `description` в `index.html` — generic («A new Flutter project.»), при желании можно заменить на описание приложения.

---

## 4. Рекомендованный порядок правок

1. **Срочно:** навигация — везде перейти на GoRouter (`context.go` / `context.push` / `context.pop`).
2. **Срочно:** Splash — проверять `AccountManagerSupabase` и добавить сохранение/восстановление сессии (SharedPreferences + загрузка из Supabase).
3. **Важно:** локализовать сообщения об ошибках входа и регистрации.
4. **Важно:** подключить `AppTheme` (светлая/тёмная тема) в `main.dart`.
5. **Важно:** исправить логику PIN при создании новой компании и использование `id` в `addProduct`.
6. **Потом:** доработать `canViewDepartment` для management, значение по умолчанию для секции кухни, убрать неиспользуемые импорты/сервисы по желанию.

---

## 5. Структура и зависимости

- Модели, Supabase-сервисы, роутинг и провайдеры в целом организованы нормально.
- `pubspec`: лишних тяжёлых зависимостей не видно; при необходимости можно провести точечную оптимизацию (например, по использованию `persian_datetime_picker`, `permission_handler` на web).

Аудит выполнен по состоянию кода на момент написания отчёта.

---

## 6. Выполненные исправления (после аудита)

- **Splash**: проверка через `AccountManagerSupabase.isLoggedInSync`; перед проверкой вызывается `initialize()`; задержка уменьшена до 500 мс.
- **Сессия**: при логине сохраняются `employee_id` и `establishment_id` в SharedPreferences; при старте выполняется `_restoreSession`; при логауте хранилище очищается.
- **Навигация**: во всех экранах Navigator заменён на GoRouter (`context.go`, `context.push`, `context.pop`).
- **Тема**: в `main` используются `AppTheme.lightTheme`, `AppTheme.darkTheme`, `themeMode: ThemeMode.system`.
- **Локализация ошибок**: добавлены ключи `company_not_found`, `invalid_email_or_password`, `login_error`, `register_error`; в Login/Register используются `localization.t(...)`.
- **Регистрация**: при создании новой компании передаётся PIN из формы в `createEstablishment(pinCode: ...)`; для кухни по умолчанию задаётся `_selectedSection = 'hot_kitchen'`.
- **Establishment.create**: добавлен опциональный параметр `pinCode`; если передан и длина 8, используется он, иначе генерируется новый.
- **ProductStoreSupabase.addProduct**: в список добавляется продукт из ответа `insertData` (`Product.fromJson(response)`), а не переданный.
- **Employee.canViewDepartment('management')**: учтены роли `manager`, `general_manager`, `assistant_manager`.
- **main**: удалён неиспользуемый импорт `flutter_localizations`.
