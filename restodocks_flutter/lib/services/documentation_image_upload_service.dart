import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'image_service.dart';
import 'supabase_service.dart';

const _bucket = 'document_images';
const _maxBytes = 250 * 1024; // 250 KB как у фото профиля

/// Загрузка изображений для документов в Supabase Storage со сжатием.
class DocumentationImageUploadService {
  static Future<String?> pickAndUploadImage() async {
    Uint8List? bytes;
    if (kIsWeb) {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return null;
      bytes = result.files.single.bytes;
    } else {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (file == null) return null;
      bytes = await file.readAsBytes();
    }
    if (bytes == null || bytes.isEmpty) return null;
    return uploadImage(bytes);
  }

  static Future<String?> takePhotoAndUpload() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return uploadImage(bytes);
  }

  static Future<String?> uploadImage(Uint8List bytes) async {
    final compressed = await ImageService().compressToMaxBytes(bytes, maxBytes: _maxBytes) ?? bytes;
    final path = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final supabase = SupabaseService();
    await supabase.client.storage
        .from(_bucket)
        .uploadBinary(path, compressed, fileOptions: const FileOptions(upsert: true));
    final url = supabase.client.storage.from(_bucket).getPublicUrl(path);
    return '$url?t=${DateTime.now().millisecondsSinceEpoch}';
  }
}
