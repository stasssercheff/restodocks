# Локальный запуск Restodocks Demo

Запуск приложения локально — без деплоя в Vercel. Подключение к тому же Supabase, что и restodocks-demo.vercel.app.

## Как запустить

```bash
cd restodocks_flutter
./run_demo_local.sh
```

Либо вручную:

```bash
cd restodocks_flutter
flutter pub get
flutter run -d web-server
```

После старта в терминале появится ссылка вида `http://localhost:xxxxx`. Откройте её в **Safari** (или любом браузере).

## Требования

- Flutter 3.38+ (stable)
- Тот же Supabase-проект, что и demo: данные и учётные записи общие

## Важно

- **Без деплоев** — изменения видны сразу при hot reload / перезапуске.
- Локально и на сайте используется одна база: то, что меняете локально, сразу отражается в demo.
- Для продакшн-подобной проверки: `flutter run -d web-server --release` (медленнее стартует, но поведение ближе к prod).
