/// Форматирование прошедшего времени с [createdAt] для списков заказов (таймер).
/// До часа: `MM:SS`, от часа: `H:MM:SS`.
String formatPosOrderLiveDuration(DateTime createdAt) {
  final now = DateTime.now();
  var start = createdAt;
  if (start.isUtc) start = start.toLocal();
  var d = now.difference(start);
  if (d.isNegative) d = Duration.zero;

  final totalSec = d.inSeconds;
  final h = totalSec ~/ 3600;
  final m = (totalSec % 3600) ~/ 60;
  final s = totalSec % 60;

  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
