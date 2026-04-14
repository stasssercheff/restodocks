// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

String _mimeForFileName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.xlsx')) {
    return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  }
  if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
  if (lower.endsWith('.csv')) return 'text/csv;charset=utf-8';
  if (lower.endsWith('.png')) return 'image/png';
  return 'application/octet-stream';
}

/// Скачивание файла в браузере.
///
/// Нельзя сразу вызывать [Url.revokeObjectUrl] после программного `click()` —
/// в Safari (в т.ч. приватный режим) загрузка не успевает стартовать и «ничего не происходит».
Future<void> saveFileBytes(String fileName, List<int> bytes) async {
  final blob = html.Blob([bytes], _mimeForFileName(fileName));
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  Future<void>.delayed(const Duration(seconds: 2), () {
    html.Url.revokeObjectUrl(url);
  });
}
