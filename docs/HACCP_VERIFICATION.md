# Проверка работоспособности: журналы ХАССП и фритюрные жиры

## Что проверено

### 1. Запуск приложения
- `flutter run -d chrome` — приложение успешно запускается в Chrome.
- `flutter build web` — сборка для web проходит без ошибок.

### 2. Цепочка «Учёт фритюрных жиров»
- **Типы:** `HaccpLogType.supportedInApp` содержит 6 журналов (5 СанПиН + fryingOil).  
  `fromCode('frying_oil')` возвращает `HaccpLogType.fryingOil`.
- **Модель:** `HaccpLog.fromQualityJson()` корректно парсит поля:  
  `oil_name`, `organoleptic_start`, `frying_equipment_type`, `frying_product_type`,  
  `frying_end_time`, `organoleptic_end`, `carry_over_kg`, `utilized_kg`, `commission_signatures`.
- **Сохранение:** форма передаёт все поля в `insertQuality()`; сервис пишет их в `haccp_quality_logs` (нужна миграция с новыми колонками).
- **Роуты:** `/haccp-journals/frying_oil`, `/haccp-journals/frying_oil/add` — экраны получают `logTypeCode: 'frying_oil'`, форма и список работают по `supportedInApp`.
- **Просмотр и PDF:** таблица в списке журнала и на экране записи использует те же поля; PDF-экспорт строит страницу по макету Приложения 8.

### 3. Автотесты
- Файл: `test/haccp_frying_oil_test.dart`.
- Запуск: `flutter test test/haccp_frying_oil_test.dart`.
- Проверки: состав `supportedInApp`, `fromCode('frying_oil')`, таблица quality, парсинг полей фритюрных жиров из JSON. Все 4 теста проходят.

### 4. Неподдерживаемые журналы
- При открытии журнала не из `supportedInApp` (например по старой ссылке) показывается экран «Этот журнал больше не поддерживается» и кнопка «К списку журналов»; возврат выполняется через `context.pop()`.

## Что нужно для полной работы

1. **Миграция БД:** выполнить в Supabase SQL Editor содержимое  
   `supabase/migrations/20260328000000_haccp_quality_frying_oil_columns.sql`.  
   Без неё сохранение записи «Учёт фритюрных жиров» завершится ошибкой из-за отсутствующих колонок.

2. **Настройки:** в разделе «Журналы и ХАССП» включить журнал «Учёт фритюрных жиров», чтобы он отображался в списке на главной странице журналов.

## Запуск проверки

```bash
cd restodocks_flutter
flutter test test/haccp_frying_oil_test.dart
flutter build web --no-tree-shake-icons --no-wasm-dry-run
```
