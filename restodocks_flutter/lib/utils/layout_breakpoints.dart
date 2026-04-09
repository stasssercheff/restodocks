import 'package:flutter/material.dart';

/// «Узкий» интерфейс как на телефоне: по **короткой** стороне экрана.
/// В альбоме [Size.width] часто > 600, но устройство всё ещё телефон — ориентироваться
/// на width нельзя, иначе включается планшетная вёрстка и раздуваются панели/кнопки.
bool isHandheldNarrowLayout(BuildContext context) {
  return MediaQuery.sizeOf(context).shortestSide < 600;
}
