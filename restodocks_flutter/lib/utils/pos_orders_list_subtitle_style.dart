import 'package:flutter/material.dart';
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
