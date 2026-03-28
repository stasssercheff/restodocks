import '../services/localization_service.dart';

/// Одна строка «этаж · зал» для стола (диалог заказа, карточка заказа и т.п.).
String posFloorRoomSummaryLine(
  LocalizationService loc, {
  String? floorName,
  String? roomName,
}) {
  final floor = floorName?.trim();
  final room = roomName?.trim();
  final floorPart = (floor == null || floor.isEmpty)
      ? loc.t('pos_tables_tab_floor_default')
      : loc.t('pos_tables_tab_floor_named', args: {'name': floor});
  final roomPart = (room == null || room.isEmpty)
      ? loc.t('pos_tables_tab_room_default')
      : loc.t('pos_tables_tab_room_named', args: {'name': room});
  return '$floorPart · $roomPart';
}
