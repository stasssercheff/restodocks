/// Скачивание файла (заглушка для не-web платформ)
Future<void> saveFileBytes(String fileName, List<int> bytes) async {
  // На мобильных/десктопе можно сохранить через path_provider + File
  // Пока просто no-op; при необходимости добавить platform-specific код
  await Future<void>.value();
}
