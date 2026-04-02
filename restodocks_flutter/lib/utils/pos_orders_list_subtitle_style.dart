import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/pos_orders_display_settings_service.dart';

/// Стиль подписи строки в списках заказов POS (учитывает настройку размера).
TextStyle? posOrderListSubtitleStyle(BuildContext context) {
  final base = Theme.of(context).textTheme.bodySmall;
  final scale = context
      .watch<PosOrdersDisplaySettingsService>()
      .listSubtitleScaleFactor;
  if (base == null) return null;
  final fs = base.fontSize ?? 13;
  return base.copyWith(fontSize: fs * scale);
}

/// Дата и время создания заказа в списках POS (локаль пользователя).
String formatPosOrderListCreatedAt(DateTime createdAt, String localeName) {
  final local = createdAt.toLocal();
  final d = DateFormat.yMd(localeName).format(local);
  final t = DateFormat.Hm(localeName).format(local);
  return '$d $t';
}
