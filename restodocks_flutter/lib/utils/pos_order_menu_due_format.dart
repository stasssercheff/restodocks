import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/account_manager_supabase.dart';
import 'number_format_utils.dart';

/// Сумма к оплате по ценам ТТК (как в списках и на карточке заказа).
String formatPosOrderMenuDue(BuildContext context, double amount) {
  final account = context.read<AccountManagerSupabase>();
  final est = account.establishment;
  final currency = est?.defaultCurrency ?? 'RUB';
  final sym =
      est?.currencySymbol ?? Establishment.currencySymbolFor(currency);
  final numStr = NumberFormatUtils.formatSum(amount, currency);
  return '$numStr $sym';
}
