import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Сохранение файла на мобильных и десктопных платформах (как инвентаризация).
Future<void> saveFileBytes(String fileName, List<int> bytes) async {
  final directory = await getApplicationDocumentsDirectory();
  final path = '${directory.path}/$fileName';
  final file = File(path);
  await file.writeAsBytes(bytes);
}
