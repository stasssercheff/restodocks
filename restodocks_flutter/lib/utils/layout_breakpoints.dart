import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// «Узкий» интерфейс как на телефоне: по **короткой** стороне экрана.
/// В альбоме [Size.width] часто > 600, но устройство всё ещё телефон — ориентироваться
/// на width нельзя, иначе включается планшетная вёрстка и раздуваются панели/кнопки.
bool isHandheldNarrowLayout(BuildContext context) {
  return MediaQuery.sizeOf(context).shortestSide < 600;
}

/// Нативный телефон в **альбоме** с заметным горизонтальным safe area (чёлка, камера,
/// Dynamic Island). На экранах без выреза (например iPhone 8) боковые inset’ы малы —
/// допустимо тянуть контент на всю ширину.
bool isNativePhoneLandscapeWithSensorHousingInsets(BuildContext context) {
  if (kIsWeb) return false;
  final mq = MediaQuery.of(context);
  if (mq.orientation != Orientation.landscape) return false;
  if (mq.size.shortestSide >= 600) return false;
  final maxSide = math.max(
    math.max(mq.viewPadding.left, mq.viewPadding.right),
    math.max(mq.padding.left, mq.padding.right),
  );
  return maxSide > 18;
}
