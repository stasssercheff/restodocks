import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

import 'image_service_storage_io.dart' if (dart.library.html) 'image_service_storage_web.dart' as _storage;

/// Размеры изображений для разных платформ
enum ImageSize {
  thumbnail, // Маленькое превью (200x200)
  medium,    // Средний размер (400x400)
  full,      // Полный размер (800x800)
}

/// Сервис для обработки изображений
class ImageService {
  static final ImageService _instance = ImageService._internal();
  factory ImageService() => _instance;
  ImageService._internal();

  final ImagePicker _imagePicker = ImagePicker();

  /// Максимальные размеры для каждого типа
  Size getMaxSize(ImageSize size) {
    switch (size) {
      case ImageSize.thumbnail:
        return const Size(200, 200);
      case ImageSize.medium:
        return const Size(400, 400);
      case ImageSize.full:
        return const Size(800, 800);
    }
  }

  /// Качество сжатия для каждого типа
  int getCompressionQuality(ImageSize size) {
    switch (size) {
      case ImageSize.thumbnail:
        return 70;
      case ImageSize.medium:
        return 80;
      case ImageSize.full:
        return 90;
    }
  }

  /// Автоматическое определение оптимального размера
  ImageSize get optimalSize {
    // В веб версии используем полный размер
    // В мобильных приложениях можно определить по размеру экрана
    return ImageSize.full;
  }

  /// Выбор изображения из галереи
  Future<XFile?> pickImageFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      return image;
    } catch (e) {
      print('Ошибка выбора изображения из галереи: $e');
      return null;
    }
  }

  /// Съемка фото с камеры
  Future<XFile?> takePhotoWithCamera() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      return photo;
    } catch (e) {
      print('Ошибка съемки фото: $e');
      return null;
    }
  }

  /// Ресайз изображения
  Future<Uint8List?> resizeImage(Uint8List imageBytes, ImageSize size) async {
    try {
      final img.Image? originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) return null;

      final Size maxSize = getMaxSize(size);

      // Расчет новых размеров с сохранением пропорций
      double newWidth = originalImage.width.toDouble();
      double newHeight = originalImage.height.toDouble();

      if (newWidth > maxSize.width) {
        newHeight = (newHeight * maxSize.width) / newWidth;
        newWidth = maxSize.width;
      }

      if (newHeight > maxSize.height) {
        newWidth = (newWidth * maxSize.height) / newHeight;
        newHeight = maxSize.height;
      }

      // Ресайз изображения
      final img.Image resizedImage = img.copyResize(
        originalImage,
        width: newWidth.round(),
        height: newHeight.round(),
      );

      // Кодирование в JPEG
      final int quality = getCompressionQuality(size);
      return img.encodeJpg(resizedImage, quality: quality);
    } catch (e) {
      print('Ошибка ресайза изображения: $e');
      return null;
    }
  }

  /// Обработка изображения (ресайз + оптимизация)
  Future<Uint8List?> processImage(Uint8List imageBytes, {ImageSize? size}) async {
    final ImageSize targetSize = size ?? optimalSize;
    return resizeImage(imageBytes, targetSize);
  }

  /// Конвертация XFile в Uint8List
  Future<Uint8List?> xFileToBytes(XFile xFile) async {
    try {
      return await xFile.readAsBytes();
    } catch (e) {
      print('Ошибка чтения файла: $e');
      return null;
    }
  }

  /// Сохранение изображения в локальное хранилище (на web — недоступно, возвращает null)
  Future<String?> saveImageToLocal(Uint8List imageBytes, String filename) async {
    try {
      return await _storage.saveImageToLocal(imageBytes, filename);
    } catch (e) {
      return null;
    }
  }

  /// Загрузка изображения из локального хранилища (на web — недоступно)
  Future<Uint8List?> loadImageFromLocal(String filename) async {
    try {
      return await _storage.loadImageFromLocal(filename);
    } catch (e) {
      return null;
    }
  }

  /// Удаление изображения из локального хранилища (на web — no-op)
  Future<bool> deleteImageFromLocal(String filename) async {
    try {
      return await _storage.deleteImageFromLocal(filename);
    } catch (e) {
      return false;
    }
  }

  /// Создание круглого аватара
  Future<Uint8List?> createCircularAvatar(Uint8List imageBytes, {int size = 100}) async {
    try {
      final img.Image? originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) return null;

      // Создание квадратного изображения
      final int minSize = originalImage.width < originalImage.height
          ? originalImage.width
          : originalImage.height;

      final img.Image squareImage = img.copyCrop(
        originalImage,
        x: (originalImage.width - minSize) ~/ 2,
        y: (originalImage.height - minSize) ~/ 2,
        width: minSize,
        height: minSize,
      );

      // Ресайз до нужного размера
      final img.Image resizedImage = img.copyResize(squareImage, width: size, height: size);

      return img.encodeJpg(resizedImage, quality: 90);
    } catch (e) {
      print('Ошибка создания аватара: $e');
      return null;
    }
  }

  /// Полная обработка изображения для профиля
  Future<Uint8List?> processProfileImage(Uint8List imageBytes) async {
    // Сначала ресайзим
    final Uint8List? resizedBytes = await processImage(imageBytes, size: ImageSize.medium);
    if (resizedBytes == null) return null;

    // Затем создаем круглый аватар
    return createCircularAvatar(resizedBytes, size: 200);
  }

  /// Проверка размера файла
  bool isValidImageSize(Uint8List bytes, {int maxSizeInMB = 10}) {
    final int maxSizeInBytes = maxSizeInMB * 1024 * 1024;
    return bytes.length <= maxSizeInBytes;
  }

  /// Получение информации об изображении
  Map<String, dynamic> getImageInfo(Uint8List bytes) {
    try {
      final img.Image? image = img.decodeImage(bytes);
      if (image == null) {
        return {'error': 'Не удалось декодировать изображение'};
      }

      return {
        'width': image.width,
        'height': image.height,
        'fileSize': bytes.length,
        'fileSizeMB': (bytes.length / (1024 * 1024)).toStringAsFixed(2),
      };
    } catch (e) {
      return {'error': 'Ошибка анализа изображения: $e'};
    }
  }
}