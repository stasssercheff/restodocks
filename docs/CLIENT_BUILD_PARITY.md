# Соответствие клиентов: сайт (web) и приложение (iOS)

Один репозиторий (`restodocks_flutter`), один бэкенд (Supabase). **Сайт и приложение совпадают по функциям только если собраны с одного и того же (или более нового) коммита Git.** Деплой сайта не обновляет установленное приложение в App Store.

Этот файл — **учёт вручную**: команда заполняет таблицу после деплоя сайта и после выкладки билда в App Store Connect. Сайт и пайплайны деплоя не меняются.

## Сборка IPA для App Store / TestFlight

Предпочтительно: `restodocks_flutter/build_ipa_testflight.sh` (внутри — `flutter build ipa --release` с `ios/ExportOptions-appstore.plist`). Вручную то же самое: из `restodocks_flutter/` выполнить `flutter build ipa --release --export-options-plist=ios/ExportOptions-appstore.plist`.

## Быстрая проверка «на месте»

Из корня репозитория:

```bash
./scripts/print-client-build-metadata.sh
```

Скопируй вывод в заметку или в таблицу ниже. Перед архивом IPA в Xcode — то же самое, чтобы зафиксировать коммит билда.

## Что сравнивать

| Артефакт | Откуда взять коммит |
|----------|---------------------|
| **Прод-сайт** | Коммит ветки, с которой Cloudflare Pages собрал Production (обычно `main` для Prod). Смотри последний успешший деплой в Cloudflare / последний merge в `main` перед релизом. |
| **Beta-сайт** | Коммит ветки `staging`, если Beta смотрит на staging (см. `docs/DEPLOY_RULES.md`). |
| **iOS в App Store** | Коммит, из которого собран **последний отправленный в ASC** архив (зафиксируй скриптом в момент `Archive`). |

Если коммит IPA **старее**, чем коммит последнего прод-деплоя сайта, приложение **отстаёт** по клиентскому коду до следующего релиза в сторе.

## Таблица учёта (заполняйте сами)

Копируй блок в issue / Notion / сюда в конец файла по желанию.

```
| Дата       | Среда   | Событие           | Git branch | Git short SHA | pubspec version |
|------------|---------|-------------------|------------|---------------|-----------------|
| YYYY-MM-DD | Prod web| деплой            | main       | abc1234       | —               |
| YYYY-MM-DD | iOS     | загрузка в ASC    | main       | abc1234       | 1.0.1+5         |
```

Версия из `pubspec.yaml` (`version:`) должна совпадать с тем, что указано для билда в App Store Connect.

## Связанные документы

- `docs/DEPLOY_RULES.md` — ветки Prod / Beta для сайта.
- `restodocks_flutter/CLOUDFLARE_DEPLOY.md` — напоминание про ветки Flutter web.
