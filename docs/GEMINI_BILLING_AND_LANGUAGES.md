# Настройка бюджета Gemini и сокращение языков до ru/en

## Часть 1: Лимит расходов (бюджет) в Google Cloud

### Шаг 1. Подключить биллинг

1. Откройте [Google Cloud Console](https://console.cloud.google.com)
2. Выберите или создайте проект
3. **Billing** (Биллинг) → **Link a billing account** / **Управление учётными записями выставления счётa**
4. Добавьте способ оплаты (карта)

> AI Studio (Gemini API) использует тот же биллинг, что и Google Cloud. Если у вас уже включён биллинг для Supabase/других сервисов — переходите к Шагу 2.

### Шаг 2. Создать бюджет (Budget) с уведомлениями

1. [Google Cloud Console](https://console.cloud.google.com) → **Billing** → **Budget & alerts**
2. Нажмите **Create budget** / **Создать бюджет**
3. Укажите:
   - **Name:** `Gemini API limit`
   - **Scope:** весь проект или конкретный billing account
   - **Amount:** например `50` USD в месяц
4. Нажмите **Next**
5. **Set alerts:**
   - 50% — `$25`
   - 90% — `$45`
   - 100% — `$50`
6. Укажите email для уведомлений
7. Нажмите **Finish**

### Шаг 3. Опционально: отключить при превышении

В Google Cloud бюджеты по умолчанию только уведомляют. Чтобы ограничить траты:

1. **Billing** → **Budgets** → выберите бюджет
2. В разделе **Actions** можно настроить **Pub/Sub** или **Cloud Function**, чтобы при достижении 100% отключать/ограничивать использование API

Проще всего — положиться на алерты и вручную отключить/удалить ключ при достижении лимита.

### Шаг 4. Проверить использование Gemini

1. [AI Studio](https://aistudio.google.com) → **Usage** — смотреть запросы и токены
2. Или: [Google Cloud Console](https://console.cloud.google.com) → **APIs & Services** → **Credentials** → ключ Gemini API → **Quotas & metrics**

---

## Часть 2: Сокращение языков до ru и en

### Что нужно изменить

| Файл | Изменение |
|------|-----------|
| `restodocks_flutter/lib/services/localization_service.dart` | `supportedLocales` и `productLanguageCodes` — оставить только `ru` и `en` |
| `restodocks_flutter/lib/services/translation_manager.dart` | `_supportedLanguages` — только `['ru', 'en']` |
| Экраны регистрации, логина, настроек | Селекторы используют `LocalizationService.supportedLocales` — обновятся автоматически |
| База `translations` | Записи de, fr, es можно оставить; новые переводы будут только ru↔en |

### 1. `lib/services/localization_service.dart`

**Строки 14–23.** Было:
```dart
static const List<Locale> supportedLocales = [
  Locale('ru', 'RU'),
  Locale('en', 'US'),
  Locale('es', 'ES'),
  Locale('de', 'DE'),
  Locale('fr', 'FR'),
];

static const List<String> productLanguageCodes = ['ru', 'en', 'es', 'de', 'fr'];
```

**Сделать:**
```dart
static const List<Locale> supportedLocales = [
  Locale('ru', 'RU'),
  Locale('en', 'US'),
];

static const List<String> productLanguageCodes = ['ru', 'en'];
```

### 2. `lib/services/translation_manager.dart`

**Строка 10.** Было:
```dart
static const List<String> _supportedLanguages = ['ru', 'en', 'de', 'fr', 'es'];
```

**Сделать:**
```dart
static const List<String> _supportedLanguages = ['ru', 'en'];
```

### 3. Экраны (обновятся автоматически)

Они используют `LocalizationService.supportedLocales`, `productLanguageCodes` и `availableLanguages` — всё выводится из этих полей. После правок в Части 2.1 и 2.2 менять экраны не нужно:
- `login_screen.dart` — строка 282
- `company_registration_screen.dart` — строка 192
- `main.dart` — строка 62
- `nomenclature_screen.dart` — строки 114, 424, 573, 967, 2083, 2267, 2701
- `product_upload_screen.dart` — строка 2008
- `tech_card_edit_screen.dart` — строка 673

### 4. Файл переводов (опционально)

`assets/translations/localizable.json` — можно удалить секции `es`, `de`, `fr`, если они есть, но это не обязательно. Приложение будет работать и с ними.

### Ожидаемый эффект

- При добавлении 129 продуктов: вместо ~516 AI-переводов (129 × 4 языков) станет ~129 (только ru↔en)
- Снижение нагрузки на Gemini примерно в 4 раза для массового добавления

---

## Часть 3: Порядок действий

1. Подключить биллинг и создать бюджет (Часть 1)
2. Включить платный тариф Gemini — лимиты повысятся
3. Сократить языки до ru и en (Часть 2) — при желании уменьшить расходы
4. При необходимости реализовать ограничения AI в `_UploadProgressDialog` (например, вариант A или D из предложений)
