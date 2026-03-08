import 'package:flutter/foundation.dart';

import 'account_manager_supabase.dart';
import 'employee_message_service.dart';

/// Счётчик непрочитанных диалогов для бейджа на «Сообщения».
class UnreadMessagesNotifier extends ChangeNotifier {
  UnreadMessagesNotifier(this._accountManager, this._msgService);

  final AccountManagerSupabase _accountManager;
  final EmployeeMessageService _msgService;

  int _count = 0;
  int get unreadCount => _count;

  Future<void> refresh() async {
    final emp = _accountManager.currentEmployee;
    final est = _accountManager.establishment;
    if (emp == null || est == null) {
      _count = 0;
      notifyListeners();
      return;
    }
    final c = await _msgService.getUnreadConversationsCount(emp.id, est.id);
    if (_count != c) {
      _count = c;
      notifyListeners();
    }
  }
}
