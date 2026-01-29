import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// Реализация локального хранилища изображений для IO-платформ (iOS, Android, desktop).
Future<String?> saveImageToLocal(Uint8List imageBytes, String filename) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/$filename';
    final file = File(filePath);
    await file.writeAsBytes(imageBytes);
    return filePath;
  } catch (e) {
    return null;
  }
}

Future<Uint8List?> loadImageFromLocal(String filename) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/$filename';
    final file = File(filePath);
    if (await file.exists()) return await file.readAsBytes();
    return null;
  } catch (e) {
    return null;
  }
}

Future<bool> deleteImageFromLocal(String filename) async {
  try {
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/$filename';
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
      return true;
    }
    return false;
  } catch (e) {
    return false;
  }
}
