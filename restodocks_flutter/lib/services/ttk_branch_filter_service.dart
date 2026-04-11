import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _keyTtkBranchFilter = 'restodocks_ttk_branch_filter';

/// Фильтр отображения ТТК по филиалам (для шефа основного заведения).
/// null = данные текущего выбранного заведения; иначе — подсветка ТТК выбранного филиала.
class TtkBranchFilterService extends ChangeNotifier {
  static final TtkBranchFilterService _instance = TtkBranchFilterService._internal();
  factory TtkBranchFilterService() => _instance;
  TtkBranchFilterService._internal();

  String? _selectedBranchId;
  String? get selectedBranchId => _selectedBranchId;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _selectedBranchId = prefs.getString(_keyTtkBranchFilter);
  }

  Future<void> setBranchFilter(String? branchId) async {
    if (_selectedBranchId == branchId) return;
    _selectedBranchId = branchId;
    final prefs = await SharedPreferences.getInstance();
    if (branchId == null) {
      await prefs.remove(_keyTtkBranchFilter);
    } else {
      await prefs.setString(_keyTtkBranchFilter, branchId);
    }
    notifyListeners();
  }
}
