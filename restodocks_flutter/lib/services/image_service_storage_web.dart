import 'dart:typed_data';

/// Заглушка для web: локальное файловое хранилище недоступно.
Future<String?> saveImageToLocal(Uint8List imageBytes, String filename) async =>
    null;

Future<Uint8List?> loadImageFromLocal(String filename) async => null;

Future<bool> deleteImageFromLocal(String filename) async => false;
