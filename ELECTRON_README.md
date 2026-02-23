# Restodocks Desktop

Десктопная версия Restodocks на базе Electron с максимальной безопасностью.

## Быстрый старт

```bash
# Автоматическая установка всего
chmod +x setup-electron.sh
./setup-electron.sh
```

## Ручная установка

1. **Node.js 18+** - [nodejs.org](https://nodejs.org)
2. **Flutter SDK** - [flutter.dev](https://flutter.dev)

```bash
# Установка зависимостей
npm install

# Сборка Flutter
npm run build-web

# Сборка Electron
npm run build-electron
```

## Безопасность 🔒

- ✅ Контекстная изоляция включена
- ✅ Node.js интеграция отключена
- ✅ Content Security Policy настроена
- ✅ Безопасный preload API
- ✅ Remote модуль отключен

## Структура файлов

```
├── electron/
│   ├── main.js          # Основной процесс
│   └── preload.js       # Безопасный API
├── restodocks_flutter/  # Flutter приложение
├── package.json         # Конфигурация Electron
├── setup-electron.sh    # Скрипт установки
└── dist/               # Собранные приложения
```

## Скрипты

```bash
# Разработка
npm start                    # Запуск с dev tools
npm run build-web           # Сборка Flutter
NODE_ENV=development npm start  # Dev режим

# Сборка
npm run build-electron      # Все платформы
npm run build-electron-win  # Только Windows
npm run build-electron-mac  # Только Mac
npm run dist               # Финальная сборка
```

## API для Flutter

В Flutter коде можно использовать:

```javascript
// В браузере будет доступно window.electronAPI
if (window.electronAPI) {
  // Открыть внешнюю ссылку
  window.electronAPI.openExternal('https://example.com');

  // Показать сообщение
  window.electronAPI.showMessage('Hello from Flutter!');

  // Выбрать файл
  const filePath = await window.electronAPI.selectFile();

  // Сохранить файл
  await window.electronAPI.saveFile('file content');
}
```

## Устранение проблем

**Приложение не запускается:**
- Проверьте что Flutter веб-приложение собрано: `npm run build-web`
- Проверьте Node.js версию: `node --version`

**Проблемы с безопасностью:**
- CSP блокирует ресурсы? Проверьте `electron/main.js` настройки CSP

**Файлы не собираются:**
- Очистите кэш: `flutter clean && npm run build-web`