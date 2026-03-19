import 'package:flutter/foundation.dart';

/// Сигнализатор для экранов, которым нужно пересчитать/досвязать вложенные ПФ
/// после импорта новых ТТК (например, чтобы "йогурт" появился в "соус салатный"
/// без повторного открытия редактирования).
class TechCardsReconcileNotifier extends ChangeNotifier {
  int _version = 0;
  DateTime? _lastMarkAt;

  int get version => _version;
  DateTime? get lastMarkAt => _lastMarkAt;

  void markTechCardsUpdated() {
    _version++;
    _lastMarkAt = DateTime.now();
    notifyListeners();
  }
}

