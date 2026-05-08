import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/models.dart';
import '../../services/services.dart';
import '../../utils/pos_floor_room_label.dart';
import '../../utils/pos_hall_permissions.dart';
import '../../utils/pos_order_menu_due_format.dart';
import '../../utils/pos_order_department.dart';
import '../../utils/pos_order_receipt_pdf.dart';
import '../../utils/pos_order_totals.dart';
import '../../widgets/app_bar_home_button.dart';
import '../../widgets/pos_marking_scanner_screen.dart';

bool _isBarDish(TechCard tc) => posLineIsBarDish(tc.category, tc.sections);

/// Карточка заказа зала: позиции из меню (ТТК).
class HallOrderDetailScreen extends StatefulWidget {
  const HallOrderDetailScreen({
    super.key,
    required this.orderId,
    this.departmentContext,
    this.presetGuestNumber,
  });

  final String orderId;

  /// `kitchen` | `bar` из `?dept=` — режим кухни/бара: без оплат, скидок и «Отдано» по строкам.
  final String? departmentContext;

  /// Предвыбранный гость при добавлении блюд (`?guest=`).
  final int? presetGuestNumber;

  @override
  State<HallOrderDetailScreen> createState() => _HallOrderDetailScreenState();
}

class _HallOrderDetailScreenState extends State<HallOrderDetailScreen> {
  PosOrder? _order;
  bool _orderLoading = true;
  /// Исключение при загрузке заказа (сеть и т.д.); null — если заказ просто не найден.
  Object? _orderLoadError;

  List<PosOrderLine> _lines = [];
  bool _linesLoading = true;
  Object? _linesError;

  List<TechCard> _menuDishes = [];
  bool _menuLoading = false;
  bool _menuLoadFailed = false;

  bool _sending = false;
  bool _closing = false;
  bool _billing = false;
  String? _markingLineId;
  bool _markingBatch = false;
  /// Загрузка сканера маркировки для строки (отличается от «отдано» [_markingLineId]).
  String? _markingScanLineId;
  bool _cancelling = false;

  final _discountCtrl = TextEditingController();
  final _servicePctCtrl = TextEditingController();
  bool _pricingSaving = false;
  List<PosOrderPayment> _payments = [];

  bool get _deptStaffView =>
      widget.departmentContext == 'kitchen' ||
      widget.departmentContext == 'bar';

  List<PosOrderLine> get _linesVisibleInDeptView {
    if (!_deptStaffView) return _lines;
    final dept = widget.departmentContext!;
    return _lines.where((l) {
      final bar = posLineIsBarForOrderLine(l);
      if (dept == 'bar') return bar;
      return !bar;
    }).toList();
  }

  bool get _busy =>
      _orderLoading ||
      _linesLoading ||
      _sending ||
      _closing ||
      _cancelling ||
      _billing ||
      _markingLineId != null ||
      _markingBatch ||
      _markingScanLineId != null;

  String _readonlyHint(PosOrder o, LocalizationService loc) {
    if (o.status == PosOrderStatus.closed) {
      return loc.t('pos_order_closed_readonly_hint');
    }
    if (o.status == PosOrderStatus.cancelled) {
      return loc.t('pos_order_cancelled_readonly_hint');
    }
    if (o.status == PosOrderStatus.sent) {
      return loc.t('pos_order_sent_readonly_hint');
    }
    return loc.t('pos_order_edit_forbidden_hint');
  }

  String _statusLabel(LocalizationService loc, PosOrderStatus s) {
    switch (s) {
      case PosOrderStatus.draft:
        return loc.t('pos_order_status_draft');
      case PosOrderStatus.sent:
        return loc.t('pos_order_status_sent');
      case PosOrderStatus.closed:
        return loc.t('pos_order_status_closed');
      case PosOrderStatus.cancelled:
        return loc.t('pos_order_status_cancelled');
    }
  }

  double _sumLinesMenuDue() {
    var s = 0.0;
    for (final l in _lines) {
      final p = l.sellingPrice;
      if (p == null) continue;
      s += l.quantity * p;
    }
    return s;
  }

  bool _linesMissingMenuPrice() =>
      _lines.any((l) => l.sellingPrice == null);

  String _paymentMethodLabel(LocalizationService loc, PosPaymentMethod m) {
    switch (m) {
      case PosPaymentMethod.cash:
        return loc.t('pos_order_payment_cash');
      case PosPaymentMethod.card:
        return loc.t('pos_order_payment_card');
      case PosPaymentMethod.transfer:
        return loc.t('pos_order_payment_transfer');
      case PosPaymentMethod.other:
        return loc.t('pos_order_payment_other');
      case PosPaymentMethod.split:
        return loc.t('pos_order_payment_split');
    }
  }

  PosOrderTotals? _totalsPreview() {
    final o = _order;
    if (o == null) return null;
    return computePosOrderTotals(
      menuSubtotal: _sumLinesMenuDue(),
      orderFields: o,
    );
  }

  Future<void> _savePricing(LocalizationService loc) async {
    final o = _order;
    if (o == null) return;
    if (o.status != PosOrderStatus.draft && o.status != PosOrderStatus.sent) {
      return;
    }
    final d =
        double.tryParse(_discountCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    final s =
        double.tryParse(_servicePctCtrl.text.replaceAll(',', '.').trim()) ?? 0;
    setState(() => _pricingSaving = true);
    try {
      await PosOrderService.instance.updateOrderPricing(
        widget.orderId,
        discountAmount: d,
        serviceChargePercent: s,
      );
      if (mounted) await _loadOrder();
    } on PosOrderNotEditableException {
      if (mounted) AppToastService.show(loc.t('pos_order_edit_forbidden'));
    } catch (e) {
      if (mounted) AppToastService.show('${loc.t('error')}: $e');
    } finally {
      if (mounted) setState(() => _pricingSaving = false);
    }
  }

  Future<void> _printReceipt(LocalizationService loc) async {
    final o = _order;
    if (o == null || _lines.isEmpty) return;
    try {
      await sharePosOrderPreReceiptPdf(
        context: context,
        order: o,
        lines: _lines,
        loc: loc,
      );
    } catch (e) {
      if (mounted) AppToastService.show('${loc.t('error')}: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reloadAll());
  }

  @override
  void dispose() {
    _discountCtrl.dispose();
    _servicePctCtrl.dispose();
    super.dispose();
  }

  void _applyPricingFieldsFromOrder(PosOrder o) {
    _discountCtrl.text =
        o.discountAmount <= 0 ? '' : _fmtNumField(o.discountAmount);
    _servicePctCtrl.text = o.serviceChargePercent <= 0
        ? ''
        : _fmtNumField(o.serviceChargePercent);
  }

  String _fmtNumField(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    final s = v.toStringAsFixed(2);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  Future<void> _loadPayments() async {
    if (_order?.status != PosOrderStatus.closed) {
      if (mounted) setState(() => _payments = []);
      return;
    }
    try {
      final list =
          await PosOrderService.instance.fetchPaymentsForOrder(widget.orderId);
      if (mounted) setState(() => _payments = list);
    } catch (_) {
      if (mounted) setState(() => _payments = []);
    }
  }

  Future<void> _loadOrder() async {
    setState(() {
      _orderLoading = true;
      _orderLoadError = null;
    });
    try {
      final o = await PosOrderService.instance.fetchById(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = o;
        _orderLoading = false;
        _orderLoadError = null;
      });
      if (o != null) _applyPricingFieldsFromOrder(o);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _order = null;
        _orderLoading = false;
        _orderLoadError = e;
      });
    }
  }

  Future<void> _reloadAll() async {
    await _loadOrder();
    if (!mounted) return;
    if (_orderLoadError != null) {
      setState(() {
        _linesLoading = false;
        _lines = [];
        _linesError = null;
      });
      return;
    }
    if (_order == null) {
      setState(() {
        _linesLoading = false;
        _lines = [];
        _linesError = null;
      });
      return;
    }
    await _refreshLines();
    if (!mounted) return;
    await _loadMenu();
    if (!mounted) return;
    await _loadPayments();
  }

  Future<void> _submit(LocalizationService loc) async {
    if (_lines.isEmpty) {
      AppToastService.show(loc.t('pos_order_send_empty'));
      return;
    }
    setState(() => _sending = true);
    try {
      await PosOrderService.instance.submitOrder(widget.orderId);
      if (!mounted) return;
      AppToastService.show(loc.t('pos_order_sent_toast'));
      await _loadOrder();
      await _refreshLines();
    } on PosOrderNotEditableException {
      if (mounted) AppToastService.show(loc.t('pos_order_edit_forbidden'));
    } on PosOrderSubmitEmptyException {
      if (mounted) AppToastService.show(loc.t('pos_order_send_empty'));
    } catch (e) {
      if (mounted) AppToastService.show('${loc.t('error')}: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _requestBill(LocalizationService loc) async {
    setState(() => _billing = true);
    try {
      await PosOrderService.instance.markTableBillRequested(widget.orderId);
      if (!mounted) return;
      AppToastService.show(loc.t('pos_order_request_bill_toast'));
      await _loadOrder();
    } catch (e) {
      if (mounted) AppToastService.show('${loc.t('error')}: $e');
    } finally {
      if (mounted) setState(() => _billing = false);
    }
  }

  Future<void> _confirmClose(BuildContext context, LocalizationService loc) async {
    final o = _order;
    if (o == null) return;
    final menuSub = _sumLinesMenuDue();
    final tipsCtrl = TextEditingController(text: '0');
    var method = PosPaymentMethod.cash;
    var split = false;
    final splitA = TextEditingController();
    final splitB = TextEditingController();
    var methodB = PosPaymentMethod.card;
    _CloseBillResult? result;
    try {
      result = await showDialog<_CloseBillResult>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setLocal) {
            double tipsVal() =>
                double.tryParse(tipsCtrl.text.replaceAll(',', '.').trim()) ?? 0;
            final grand = computePosOrderTotalsRaw(
              menuSubtotal: menuSub,
              discountAmount: o.discountAmount,
              serviceChargePercent: o.serviceChargePercent,
              tipsAmount: tipsVal(),
            ).grandTotal;
            if (split && splitA.text.isEmpty && splitB.text.isEmpty) {
              final h = grand / 2;
              splitA.text = h.toStringAsFixed(2);
              splitB.text = (grand - h).toStringAsFixed(2);
            }
            return AlertDialog(
              title: Text(loc.t('pos_order_close')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(loc.t('pos_order_close_confirm')),
                    const SizedBox(height: 12),
                    TextField(
                      controller: tipsCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: loc.t('pos_order_tips_label'),
                      ),
                      onChanged: (_) => setLocal(() {}),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${loc.t('pos_order_grand_total_label')}: ${formatPosOrderMenuDue(ctx, grand)}',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(loc.t('pos_order_split_payment')),
                      value: split,
                      onChanged: (v) {
                        setLocal(() {
                          split = v;
                          if (v) {
                            final h = grand / 2;
                            splitA.text = h.toStringAsFixed(2);
                            splitB.text = (grand - h).toStringAsFixed(2);
                          }
                        });
                      },
                    ),
                    if (!split) ...[
                      Text(
                        loc.t('pos_order_payment_label'),
                        style: Theme.of(ctx).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      DropdownButton<PosPaymentMethod>(
                        isExpanded: true,
                        value: method,
                        items: [
                          DropdownMenuItem(
                            value: PosPaymentMethod.cash,
                            child: Text(loc.t('pos_order_payment_cash')),
                          ),
                          DropdownMenuItem(
                            value: PosPaymentMethod.card,
                            child: Text(loc.t('pos_order_payment_card')),
                          ),
                          DropdownMenuItem(
                            value: PosPaymentMethod.transfer,
                            child: Text(loc.t('pos_order_payment_transfer')),
                          ),
                          DropdownMenuItem(
                            value: PosPaymentMethod.other,
                            child: Text(loc.t('pos_order_payment_other')),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setLocal(() => method = v);
                        },
                      ),
                    ] else ...[
                      TextField(
                        controller: splitA,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText:
                              '${loc.t('pos_order_payment_label')} 1',
                        ),
                        onChanged: (_) => setLocal(() {}),
                      ),
                      const SizedBox(height: 8),
                      DropdownButton<PosPaymentMethod>(
                        isExpanded: true,
                        value: method,
                        items: [
                          DropdownMenuItem(
                            value: PosPaymentMethod.cash,
                            child: Text(loc.t('pos_order_payment_cash')),
                          ),
                          DropdownMenuItem(
                            value: PosPaymentMethod.card,
                            child: Text(loc.t('pos_order_payment_card')),
                          ),
                          DropdownMenuItem(
                            value: PosPaymentMethod.transfer,
                            child: Text(loc.t('pos_order_payment_transfer')),
                          ),
                          DropdownMenuItem(
                            value: PosPaymentMethod.other,
                            child: Text(loc.t('pos_order_payment_other')),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setLocal(() => method = v);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: splitB,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText:
                              '${loc.t('pos_order_payment_label')} 2',
                        ),
                        onChanged: (_) => setLocal(() {}),
                      ),
                      const SizedBox(height: 8),
                      DropdownButton<PosPaymentMethod>(
                        isExpanded: true,
                        value: methodB,
                        items: [
                          DropdownMenuItem(
                            value: PosPaymentMethod.cash,
                            child: Text(loc.t('pos_order_payment_cash')),
                          ),
                          DropdownMenuItem(
                            value: PosPaymentMethod.card,
                            child: Text(loc.t('pos_order_payment_card')),
                          ),
                          DropdownMenuItem(
                            value: PosPaymentMethod.transfer,
                            child: Text(loc.t('pos_order_payment_transfer')),
                          ),
                          DropdownMenuItem(
                            value: PosPaymentMethod.other,
                            child: Text(loc.t('pos_order_payment_other')),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setLocal(() => methodB = v);
                        },
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(loc.t('cancel')),
                ),
                FilledButton(
                  onPressed: () {
                    final tips =
                        double.tryParse(tipsCtrl.text.replaceAll(',', '.').trim()) ?? 0;
                    final g = computePosOrderTotalsRaw(
                      menuSubtotal: menuSub,
                      discountAmount: o.discountAmount,
                      serviceChargePercent: o.serviceChargePercent,
                      tipsAmount: tips,
                    ).grandTotal;
                    late final List<({PosPaymentMethod method, double amount})>
                        parts;
                    if (!split) {
                      parts = [(method: method, amount: g)];
                    } else {
                      final a = double.tryParse(
                            splitA.text.replaceAll(',', '.').trim(),
                          ) ??
                          0;
                      final b = double.tryParse(
                            splitB.text.replaceAll(',', '.').trim(),
                          ) ??
                          0;
                      parts = [
                        (method: method, amount: a),
                        (method: methodB, amount: b),
                      ];
                    }
                    Navigator.pop(
                      ctx,
                      _CloseBillResult(tips: tips, payments: parts),
                    );
                  },
                  child: Text(loc.t('pos_order_close')),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      tipsCtrl.dispose();
      splitA.dispose();
      splitB.dispose();
    }
    if (result == null || !mounted) return;

    final tips = result.tips;
    final parts = result.payments;
    final grand = computePosOrderTotalsRaw(
      menuSubtotal: menuSub,
      discountAmount: o.discountAmount,
      serviceChargePercent: o.serviceChargePercent,
      tipsAmount: tips,
    ).grandTotal;

    setState(() => _closing = true);
    final estBefore = context.read<AccountManagerSupabase>().establishment;
    try {
      await PosOrderService.instance.closeOrder(
        widget.orderId,
        tipsAmount: tips,
        payments: parts,
        closedByEmployeeId:
            context.read<AccountManagerSupabase>().currentEmployee?.id,
      );
      if (estBefore != null) {
        await PosFiscalService.instance.queueSaleAfterOrderClose(
          establishmentId: estBefore.id,
          orderId: widget.orderId,
          grandTotal: grand,
          currencyCode: estBefore.defaultCurrency,
        );
      }
      if (!mounted) return;
      AppToastService.show(loc.t('pos_order_closed_toast'));
      await _reloadAll();
    } on PosOrderPaymentMismatchException {
      if (mounted) {
        AppToastService.show(loc.t('pos_order_payment_mismatch'));
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        if (e.code == '23514') {
          AppToastService.show(loc.t('pos_order_close_payment_error'));
        } else {
          AppToastService.show('${loc.t('error')}: $e');
        }
      }
    } catch (e) {
      if (mounted) AppToastService.show('${loc.t('error')}: $e');
    } finally {
      if (mounted) setState(() => _closing = false);
    }
  }

  Future<void> _confirmCancelOrder(LocalizationService loc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('pos_order_cancel_order')),
        content: Text(loc.t('pos_order_cancel_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.t('pos_order_cancel_order')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await PosOrderService.instance.cancelOrder(widget.orderId);
      if (!mounted) return;
      AppToastService.show(loc.t('pos_order_cancelled_toast'));
      context.pop();
    } on PosOrderNotEditableException {
      if (mounted) AppToastService.show(loc.t('pos_order_edit_forbidden'));
    } catch (e) {
      if (mounted) AppToastService.show('${loc.t('error')}: $e');
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  Future<void> _loadMenu() async {
    final account = context.read<AccountManagerSupabase>();
    final est = account.establishment;
    if (est == null) return;
    setState(() {
      _menuLoading = true;
      _menuLoadFailed = false;
    });
    try {
      final svc = context.read<TechCardServiceSupabase>();
      final all = await svc.getTechCardsForEstablishment(est.dataEstablishmentId);
      final dishes = all.where((tc) => !tc.isSemiFinished).toList();
      dishes.sort((a, b) => a.dishName.toLowerCase().compareTo(b.dishName.toLowerCase()));
      if (mounted) {
        setState(() {
          _menuDishes = dishes;
          _menuLoading = false;
          _menuLoadFailed = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _menuLoading = false;
          _menuLoadFailed = true;
          _menuDishes = [];
        });
      }
    }
  }

  Future<void> _refreshLines() async {
    setState(() {
      _linesLoading = true;
      _linesError = null;
    });
    try {
      final list = await PosOrderService.instance.fetchLines(widget.orderId);
      if (!mounted) return;
      setState(() {
        _lines = list;
        _linesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _linesError = e;
        _linesLoading = false;
      });
    }
  }

  Future<void> _addDish(
    TechCard tc,
    LocalizationService loc, {
    double quantity = 1,
    String? comment,
    int courseNumber = 1,
    int? guestNumber,
  }) async {
    try {
      await PosOrderService.instance.addLine(
        orderId: widget.orderId,
        techCardId: tc.id,
        quantity: quantity,
        comment: comment,
        courseNumber: courseNumber,
        guestNumber: guestNumber,
      );
      if (mounted) await _refreshLines();
    } on PosOrderNotEditableException {
      if (mounted) {
        AppToastService.show(loc.t('pos_order_edit_forbidden'));
      }
    } catch (e) {
      if (mounted) {
        AppToastService.show('${loc.t('error')}: $e');
      }
    }
  }

  Future<void> _setQty(PosOrderLine line, double q, LocalizationService loc) async {
    try {
      await PosOrderService.instance.updateLineQuantity(line.id, widget.orderId, q);
      if (mounted) await _refreshLines();
    } on PosOrderNotEditableException {
      if (mounted) AppToastService.show(loc.t('pos_order_edit_forbidden'));
    } catch (e) {
      if (mounted) AppToastService.show('${loc.t('error')}: $e');
    }
  }

  Future<void> _removeLine(PosOrderLine line, LocalizationService loc) async {
    try {
      await PosOrderService.instance.deleteLine(line.id, widget.orderId);
      if (mounted) await _refreshLines();
    } on PosOrderNotEditableException {
      if (mounted) AppToastService.show(loc.t('pos_order_edit_forbidden'));
    } catch (e) {
      if (mounted) AppToastService.show('${loc.t('error')}: $e');
    }
  }

  Future<void> _openMarkingScan(PosOrderLine line, LocalizationService loc) async {
    final nav = Navigator.of(context);
    setState(() => _markingScanLineId = line.id);
    try {
      final code = await nav.push<String>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (ctx) => const PosMarkingScannerScreen(),
        ),
      );
      if (!mounted || code == null || code.isEmpty) return;
      await PosOrderService.instance.appendLineMarkingCode(
        line.id,
        widget.orderId,
        code,
      );
      if (mounted) await _refreshLines();
    } on PosOrderLineMarkingDuplicateException {
      if (mounted) {
        AppToastService.show(loc.t('pos_marking_duplicate'));
      }
    } on PosOrderLineMarkingLimitException {
      if (mounted) {
        AppToastService.show(loc.t('pos_marking_limit'));
      }
    } catch (e) {
      if (mounted) AppToastService.show('${loc.t('error')}: $e');
    } finally {
      if (mounted) setState(() => _markingScanLineId = null);
    }
  }

  Future<void> _removeMarkingAt(
    PosOrderLine line,
    int index,
    LocalizationService loc,
  ) async {
    try {
      await PosOrderService.instance.removeLineMarkingCodeAt(
        line.id,
        widget.orderId,
        index,
      );
      if (mounted) await _refreshLines();
    } on PosOrderNotEditableException {
      if (mounted) AppToastService.show(loc.t('pos_order_edit_forbidden'));
    } catch (e) {
      if (mounted) AppToastService.show('${loc.t('error')}: $e');
    }
  }

  Future<void> _markLineServed(PosOrderLine line, LocalizationService loc) async {
    setState(() => _markingLineId = line.id);
    try {
      await PosOrderService.instance.markLineServed(line.id, widget.orderId);
      if (mounted) await _refreshLines();
    } on PosOrderLineMarkServedException {
      if (mounted) {
        AppToastService.show(loc.t('pos_order_line_mark_served_forbidden'));
      }
    } catch (e) {
      if (mounted) AppToastService.show('${loc.t('error')}: $e');
    } finally {
      if (mounted) setState(() => _markingLineId = null);
    }
  }

  Future<void> _markDeptLinesServed(LocalizationService loc) async {
    if (!_deptStaffView) return;
    final emp = context.read<AccountManagerSupabase>().currentEmployee;
    final dept = widget.departmentContext!;
    final targets = _lines.where((l) {
      final bar = posLineIsBarForOrderLine(l);
      if (dept == 'bar') return bar;
      return !bar;
    }).where((l) => l.servedAt == null && posCanMarkOrderLineServed(emp, l)).toList();
    if (targets.isEmpty) return;
    setState(() => _markingBatch = true);
    try {
      for (final line in targets) {
        await PosOrderService.instance.markLineServed(line.id, widget.orderId);
      }
      if (mounted) await _refreshLines();
    } on PosOrderLineMarkServedException {
      if (mounted) {
        AppToastService.show(loc.t('pos_order_line_mark_served_forbidden'));
      }
    } catch (e) {
      if (mounted) AppToastService.show('${loc.t('error')}: $e');
    } finally {
      if (mounted) setState(() => _markingBatch = false);
    }
  }

  Future<void> _editLineCourseGuest(PosOrderLine line, LocalizationService loc) async {
    final gc = (_order?.guestCount ?? 1).clamp(1, 99);
    var course = line.courseNumber.clamp(1, 8);
    var guest = line.guestNumber;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: Text(loc.t('pos_order_line_edit_course_guest_title')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    loc.t('pos_order_add_course_label'),
                    style: Theme.of(ctx).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  DropdownButton<int>(
                    isExpanded: true,
                    value: course,
                    items: [
                      for (var c = 1; c <= 8; c++)
                        DropdownMenuItem(value: c, child: Text('$c')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setLocal(() => course = v);
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    loc.t('pos_order_add_guest_label'),
                    style: Theme.of(ctx).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 4),
                  DropdownButton<int?>(
                    isExpanded: true,
                    value: guest,
                    items: [
                      DropdownMenuItem<int?>(
                        value: null,
                        child: Text(loc.t('pos_order_add_guest_any')),
                      ),
                      for (var g = 1; g <= gc; g++)
                        DropdownMenuItem(
                          value: g,
                          child: Text(
                            loc.t('pos_order_line_guest_short', args: {'n': '$g'}),
                          ),
                        ),
                    ],
                    onChanged: (v) => setLocal(() => guest = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(loc.t('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(loc.t('save')),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await PosOrderService.instance.updateLineCourseAndGuest(
        line.id,
        widget.orderId,
        courseNumber: course,
        guestNumber: guest,
      );
      if (mounted) await _refreshLines();
    } on PosOrderNotEditableException {
      if (mounted) AppToastService.show(loc.t('pos_order_edit_forbidden'));
    } catch (e) {
      if (mounted) AppToastService.show('${loc.t('error')}: $e');
    }
  }

  Future<void> _editLineComment(PosOrderLine line, LocalizationService loc) async {
    final ctrl = TextEditingController(text: line.comment ?? '');
    bool? ok;
    var snap = '';
    try {
      ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(loc.t('pos_order_line_comment')),
          content: TextField(
            controller: ctrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: loc.t('pos_order_line_comment_hint'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(loc.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(loc.t('save')),
            ),
          ],
        ),
      );
    } finally {
      snap = ctrl.text;
      ctrl.dispose();
    }
    if (ok != true || !mounted) return;
    try {
      await PosOrderService.instance
          .updateLineComment(line.id, widget.orderId, snap.trim().isEmpty ? null : snap.trim());
      if (mounted) await _refreshLines();
    } on PosOrderNotEditableException {
      if (mounted) AppToastService.show(loc.t('pos_order_edit_forbidden'));
    } catch (e) {
      if (mounted) AppToastService.show('${loc.t('error')}: $e');
    }
  }

  void _openAddDishSheet(LocalizationService loc) {
    final guestCount = (_order?.guestCount ?? 1).clamp(1, 99);
    final preset = widget.presetGuestNumber;
    final initialGuest = preset != null && preset >= 1 && preset <= guestCount
        ? preset
        : null;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return _AddDishSheet(
          loc: loc,
          dishes: _menuDishes,
          loading: _menuLoading,
          guestCount: guestCount,
          initialGuestNumber: initialGuest,
          onPick: (tc, quantity, comment, courseNumber, guestNumber) async {
            await _addDish(
              tc,
              loc,
              quantity: quantity,
              comment: comment,
              courseNumber: courseNumber,
              guestNumber: guestNumber,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = context.watch<LocalizationService>();
    final emp = context.watch<AccountManagerSupabase>().currentEmployee;
    final lang = loc.currentLanguageCode;
    final lc = Localizations.localeOf(context).toString();
    final dateFmt = DateFormat.yMMMd(lc);
    final timeFmt = DateFormat.Hm(lc);

    final canDisplaySettings = posCanConfigureOrdersDisplay(emp);

    return Scaffold(
      appBar: AppBar(
        leading: appBarBackButton(context),
        title: Text(loc.t('pos_order_detail_title')),
        actions: [
          if (canDisplaySettings)
            IconButton(
              icon: const Icon(Icons.tune_outlined),
              onPressed: _busy ? null : () => context.push('/settings/orders-display'),
              tooltip: loc.t('pos_orders_display_settings_title'),
            ),
          if (_order != null &&
              _order!.status != PosOrderStatus.cancelled &&
              _lines.isNotEmpty &&
              !_linesLoading &&
              !_deptStaffView)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: _busy ? null : () => _printReceipt(loc),
              tooltip: loc.t('pos_order_print_receipt'),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : _reloadAll,
            tooltip: loc.t('refresh'),
          ),
        ],
      ),
      floatingActionButton: () {
        final o = _order;
        if (_deptStaffView) return const SizedBox.shrink();
        final canAddDishes = o != null &&
            (o.status == PosOrderStatus.draft ||
                o.status == PosOrderStatus.sent);
        if (!canAddDishes) return const SizedBox.shrink();
        return FloatingActionButton(
          onPressed: (_menuLoading && _menuDishes.isEmpty) || _sending
              ? null
              : () => _openAddDishSheet(loc),
          tooltip: loc.t('pos_order_line_add'),
          child: const Icon(Icons.add),
        );
      }(),
      body: () {
        if (_orderLoading) {
          return const Center(child: CircularProgressIndicator());
        }
        final o = _order;
        if (o == null) {
          if (_orderLoadError != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      loc.t('pos_tables_load_error'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _reloadAll,
                      child: Text(loc.t('retry')),
                    ),
                  ],
                ),
              ),
            );
          }
          return Center(child: Text(loc.t('document_not_found')));
        }
        final tn = o.tableNumber ?? 0;
        final editable =
            o.status == PosOrderStatus.draft && !_deptStaffView;
        final canVoidSentLine = o.status == PosOrderStatus.sent &&
            !_deptStaffView &&
            posCanCloseHallOrder(emp);
        final lineRows = _deptStaffView ? _linesVisibleInDeptView : _lines;

        return RefreshIndicator(
          onRefresh: _reloadAll,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                loc.t('pos_table_number', args: {'n': '$tn'}),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 6),
              Text(
                posFloorRoomSummaryLine(loc,
                    floorName: o.floorName, roomName: o.roomName),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                '${loc.t('pos_orders_guests_short')}: ${o.guestCount}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                '${loc.t('pos_tables_field_status')}: ${_statusLabel(loc, o.status)}',
              ),
              const SizedBox(height: 8),
              Text(
                '${dateFmt.format(o.createdAt.toLocal())} ${timeFmt.format(o.createdAt.toLocal())}',
              ),
              if (!_deptStaffView &&
                  (editable || o.status == PosOrderStatus.sent) &&
                  o.status != PosOrderStatus.cancelled) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _discountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: loc.t('pos_order_discount_label'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _servicePctCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: loc.t('pos_order_service_percent_label'),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: _pricingSaving || _busy
                      ? null
                      : () => _savePricing(loc),
                  child: Text(loc.t('pos_order_apply_pricing')),
                ),
              ],
              if (!_deptStaffView &&
                  !_linesLoading &&
                  _linesError == null &&
                  _lines.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...() {
                  final t = _totalsPreview();
                  if (t == null) return <Widget>[];
                  return [
                    Text(
                      '${loc.t('pos_order_subtotal_menu_label')}: ${formatPosOrderMenuDue(context, t.menuSubtotal)}',
                    ),
                    if (t.discountAmount > 0)
                      Text(
                        '${loc.t('pos_order_discount_label')}: −${formatPosOrderMenuDue(context, t.discountAmount)}',
                      ),
                    if (t.serviceAmount > 0)
                      Text(
                        '${loc.t('pos_order_service_amount_label')}: ${formatPosOrderMenuDue(context, t.serviceAmount)}',
                      ),
                    if (t.tipsAmount > 0)
                      Text(
                        '${loc.t('pos_order_tips_label')}: ${formatPosOrderMenuDue(context, t.tipsAmount)}',
                      ),
                    const SizedBox(height: 6),
                    Text(
                      '${loc.t('pos_order_grand_total_label')}: ${formatPosOrderMenuDue(context, t.grandTotal)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if (_linesMissingMenuPrice())
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          loc.t('pos_order_total_partial'),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ),
                  ];
                }(),
              ],
              if (!_deptStaffView && o.status == PosOrderStatus.closed) ...[
                if (o.paymentMethod != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${loc.t('pos_order_payment_label')}: ${_paymentMethodLabel(loc, o.paymentMethod!)}',
                  ),
                ],
                if (o.paidAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    loc.t('pos_order_paid_at', args: {
                      'time': timeFmt.format(o.paidAt!.toLocal()),
                    }),
                  ),
                ],
                if (_payments.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ..._payments.map(
                    (p) => Text(
                      '${_paymentMethodLabel(loc, p.paymentMethod)}: ${formatPosOrderMenuDue(context, p.amount)}',
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 24),
              Text(
                loc.t('pos_order_lines_heading'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (_linesLoading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_linesError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        loc.t('pos_tables_load_error'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed:
                            _busy ? null : () => _refreshLines(),
                        child: Text(loc.t('retry')),
                      ),
                    ],
                  ),
                )
              else if (_deptStaffView &&
                  lineRows.isEmpty &&
                  _lines.isNotEmpty)
                Text(
                  loc.t('pos_order_dept_detail_empty'),
                  style: Theme.of(context).textTheme.bodyLarge,
                )
              else if (_lines.isEmpty)
                Text(
                  loc.t('pos_order_line_empty'),
                  style: Theme.of(context).textTheme.bodyLarge,
                )
              else
                ...lineRows.map((line) {
                  final canEditMarking = !_deptStaffView &&
                      (o.status == PosOrderStatus.draft ||
                          o.status == PosOrderStatus.sent);
                  return _LineTile(
                    line: line,
                    lang: lang,
                    editable: editable,
                    canVoidLine: canVoidSentLine,
                    orderStatus: o.status,
                    employee: emp,
                    timeFmt: timeFmt,
                    markingLine: _markingLineId == line.id,
                    scanningMarking: _markingScanLineId == line.id,
                    canEditMarking: canEditMarking,
                    onScanMarking: canEditMarking
                        ? () => _openMarkingScan(line, loc)
                        : null,
                    onRemoveMarking: canEditMarking
                        ? (i) => _removeMarkingAt(line, i, loc)
                        : null,
                    loc: loc,
                    compactDeptStaff: _deptStaffView,
                    onQty: (q) => _setQty(line, q, loc),
                    onDelete: () => _removeLine(line, loc),
                    onComment: () => _editLineComment(line, loc),
                    onEditCourseGuest: editable
                        ? () => _editLineCourseGuest(line, loc)
                        : null,
                    onMarkServed: _deptStaffView
                        ? null
                        : () => _markLineServed(line, loc),
                  );
                }),
              if (editable ||
                  (o.status == PosOrderStatus.sent && !_deptStaffView)) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: (_menuLoading && _menuDishes.isEmpty) || _sending
                      ? null
                      : () => _openAddDishSheet(loc),
                  icon: const Icon(Icons.restaurant_menu),
                  label: Text(loc.t('pos_order_line_add')),
                ),
                if (_menuLoadFailed) ...[
                  const SizedBox(height: 12),
                  Text(
                    loc.t('pos_tables_load_error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _menuLoading ? null : _loadMenu,
                      icon: const Icon(Icons.refresh_outlined),
                      label: Text(loc.t('retry')),
                    ),
                  ),
                ],
              ],
              if (editable) ...[
                if (!_linesLoading && _lines.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _sending ? null : () => _submit(loc),
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: Text(loc.t('pos_order_send')),
                  ),
                ],
              ],
              if (_deptStaffView &&
                  o.status == PosOrderStatus.sent &&
                  !_linesLoading &&
                  _linesError == null &&
                  lineRows.isNotEmpty) ...[
                const SizedBox(height: 16),
                if (lineRows.any((l) =>
                    l.servedAt == null &&
                    posCanMarkOrderLineServed(emp, l)))
                  FilledButton.tonalIcon(
                    onPressed: _busy
                        ? null
                        : () => _markDeptLinesServed(loc),
                    icon: _markingBatch
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.restaurant),
                    label: Text(loc.t('pos_order_line_mark_served')),
                  )
                else if (lineRows.every((l) => l.servedAt != null))
                  Text(
                    loc.t('pos_order_dept_all_served'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
              ],
              if (posCanCloseHallOrder(emp) &&
                  (o.status == PosOrderStatus.draft ||
                      o.status == PosOrderStatus.sent) &&
                  !_deptStaffView) ...[
                const SizedBox(height: 16),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: _cancelling ? null : () => _confirmCancelOrder(loc),
                  child: Text(loc.t('pos_order_cancel_order')),
                ),
                const SizedBox(height: 16),
              ],
              if (posCanCloseHallOrder(emp) &&
                  o.status != PosOrderStatus.closed &&
                  o.status != PosOrderStatus.cancelled &&
                  !_deptStaffView) ...[
                const SizedBox(height: 16),
                if (o.tableStatus != PosTableStatus.billRequested)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _requestBill(loc),
                    icon: _billing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.payments_outlined),
                    label: Text(loc.t('pos_order_request_bill')),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.notifications_active_outlined,
                          color: Colors.amber.shade800,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            loc.t('pos_order_bill_requested'),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Colors.amber.shade900,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: _closing ? null : () => _confirmClose(context, loc),
                  child: Text(loc.t('pos_order_close')),
                ),
                const SizedBox(height: 8),
                Text(
                  loc.t('pos_order_fiscal_not_configured'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
              if (!editable && !_deptStaffView) ...[
                const SizedBox(height: 16),
                Text(
                  _readonlyHint(o, loc),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        );
      }(),
    );
  }
}

class _CloseBillResult {
  _CloseBillResult({required this.tips, required this.payments});

  final double tips;
  final List<({PosPaymentMethod method, double amount})> payments;
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.line,
    required this.lang,
    required this.editable,
    this.canVoidLine = false,
    required this.orderStatus,
    required this.employee,
    required this.timeFmt,
    required this.markingLine,
    this.scanningMarking = false,
    this.canEditMarking = false,
    this.onScanMarking,
    this.onRemoveMarking,
    required this.loc,
    this.compactDeptStaff = false,
    required this.onQty,
    required this.onDelete,
    required this.onComment,
    this.onEditCourseGuest,
    this.onMarkServed,
  });

  final PosOrderLine line;
  final String lang;
  final bool editable;
  /// Снять позицию после отправки (зал).
  final bool canVoidLine;
  final PosOrderStatus orderStatus;
  final Employee? employee;
  final DateFormat timeFmt;
  final bool markingLine;
  final bool scanningMarking;
  final bool canEditMarking;
  final VoidCallback? onScanMarking;
  final void Function(int index)? onRemoveMarking;
  final LocalizationService loc;
  /// Без цен и «отдано» по строке (экран кухни/бара).
  final bool compactDeptStaff;
  final void Function(double) onQty;
  final VoidCallback onDelete;
  final VoidCallback onComment;
  final VoidCallback? onEditCourseGuest;
  final VoidCallback? onMarkServed;

  @override
  Widget build(BuildContext context) {
    final title = line.dishTitleForLang(lang);
    // Temporarily disabled in UI; can be re-enabled by changing condition.
    final showMarkingUi = line.id.startsWith('__enable_marking__');
    final sub = <String>[
      '${loc.t('pos_order_line_qty_short')}: ${_formatPosQty(line.quantity)}',
      if (line.courseNumber > 1)
        '${loc.t('pos_order_course_short')}: ${line.courseNumber}',
      if (line.guestNumber != null)
        loc.t('pos_order_line_guest_short', args: {'n': '${line.guestNumber}'}),
      if (line.comment != null && line.comment!.trim().isNotEmpty)
        line.comment!.trim(),
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (editable) ...[
                  if (onEditCourseGuest != null)
                    IconButton(
                      onPressed: onEditCourseGuest,
                      icon: const Icon(Icons.people_alt_outlined),
                      tooltip: loc.t('pos_order_line_edit_course_guest_title'),
                    ),
                  IconButton(
                    onPressed: onComment,
                    icon: Icon(
                      line.comment != null && line.comment!.trim().isNotEmpty
                          ? Icons.chat
                          : Icons.chat_outlined,
                    ),
                    tooltip: loc.t('pos_order_line_comment'),
                  ),
                ],
                if (editable || canVoidLine)
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: canVoidLine && !editable
                        ? loc.t('pos_order_line_void')
                        : loc.t('pos_order_line_delete'),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              sub,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (!compactDeptStaff && line.sellingPrice != null) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  formatPosOrderMenuDue(
                    context,
                    line.quantity * line.sellingPrice!,
                  ),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
            if (showMarkingUi &&
                !compactDeptStaff &&
                (line.markingCodes.isNotEmpty ||
                    onScanMarking != null)) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  loc.t('pos_order_line_marking_codes'),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < line.markingCodes.length; i++)
                    InputChip(
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 220),
                        child: Text(
                          line.markingCodes[i],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      onDeleted: onRemoveMarking != null
                          ? () => onRemoveMarking!(i)
                          : null,
                    ),
                  if (onScanMarking != null)
                    ActionChip(
                      avatar: scanningMarking
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.qr_code_scanner, size: 20),
                      label: Text(loc.t('pos_order_line_scan_marking')),
                      onPressed: scanningMarking ? null : onScanMarking,
                    ),
                ],
              ),
              if (canEditMarking)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    loc.t('pos_order_line_marking_hint'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
            ],
            if (!compactDeptStaff && line.servedAt != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(
                    Icons.check_circle,
                    size: 18,
                    color: Colors.green.shade700,
                  ),
                  label: Text(
                    loc.t('pos_order_line_served_at', args: {
                      'time': timeFmt.format(line.servedAt!.toLocal()),
                    }),
                  ),
                ),
              ),
            ],
            if (!compactDeptStaff &&
                !editable &&
                orderStatus == PosOrderStatus.sent &&
                line.servedAt == null &&
                onMarkServed != null &&
                posCanMarkOrderLineServed(employee, line)) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: markingLine
                    ? const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : FilledButton.tonalIcon(
                        onPressed: onMarkServed,
                        icon: const Icon(Icons.restaurant),
                        label: Text(loc.t('pos_order_line_mark_served')),
                      ),
              ),
            ],
            if (editable) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    onPressed: line.quantity <= 1
                        ? null
                        : () => onQty(line.quantity - 1),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text(_formatPosQty(line.quantity),
                      style: Theme.of(context).textTheme.titleMedium),
                  IconButton(
                    onPressed: () => onQty(line.quantity + 1),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _editQtyDialog(context, line, onQty, loc),
                    child: Text(loc.t('pos_order_line_qty_edit')),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

}

String _formatPosQty(double q) {
  final t = q.toStringAsFixed(2);
  return t.replaceFirst(RegExp(r'\.?0+$'), '');
}

Future<void> _editQtyDialog(
  BuildContext context,
  PosOrderLine line,
  void Function(double) onQty,
  LocalizationService loc,
) async {
  final ctrl = TextEditingController(text: _formatPosQty(line.quantity));
  bool? ok;
  String textSnapshot = '';
  try {
    ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.t('pos_order_line_qty_edit')),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(labelText: loc.t('pos_order_line_qty')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.t('save')),
          ),
        ],
      ),
    );
    textSnapshot = ctrl.text;
  } finally {
    ctrl.dispose();
  }
  if (ok != true || !context.mounted) return;
  final raw = textSnapshot.replaceAll(',', '.').trim();
  final v = double.tryParse(raw);
  if (v == null || v <= 0) {
    AppToastService.show(loc.t('pos_order_line_qty_invalid'));
    return;
  }
  onQty(v);
}

class _AddDishSheet extends StatefulWidget {
  const _AddDishSheet({
    required this.loc,
    required this.dishes,
    required this.loading,
    required this.guestCount,
    this.initialGuestNumber,
    required this.onPick,
  });

  final LocalizationService loc;
  final List<TechCard> dishes;
  final bool loading;
  final int guestCount;
  final int? initialGuestNumber;
  final Future<void> Function(
    TechCard tc,
    double quantity,
    String? comment,
    int courseNumber,
    int? guestNumber,
  )
      onPick;

  @override
  State<_AddDishSheet> createState() => _AddDishSheetState();
}

class _AddDishSheetState extends State<_AddDishSheet> {
  final _search = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _comment = TextEditingController();
  String _tab = 'kitchen';
  int _course = 1;
  int? _guest;
  TechCard? _selectedDish;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    final g = widget.initialGuestNumber;
    if (g != null && g >= 1 && g <= widget.guestCount) {
      _guest = g;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _qty.dispose();
    _comment.dispose();
    super.dispose();
  }

  List<TechCard> get _filtered {
    var list = widget.dishes.where((tc) {
      if (_tab == 'bar') return _isBarDish(tc);
      return !_isBarDish(tc);
    }).toList();
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((tc) {
      if (tc.dishName.toLowerCase().contains(q)) return true;
      final loc = tc.dishNameLocalized?.values.any((v) => v.toLowerCase().contains(q));
      return loc == true;
    }).toList();
  }

  Future<void> _confirmAdd(LocalizationService loc) async {
    final tc = _selectedDish;
    if (tc == null) return;
    final qtyRaw = _qty.text.replaceAll(',', '.').trim();
    final qty = double.tryParse(qtyRaw);
    if (qty == null || qty <= 0) {
      AppToastService.show(loc.t('pos_order_line_qty_invalid'));
      return;
    }
    if (_adding) return;
    setState(() => _adding = true);
    try {
      final comment = _comment.text.trim();
      await widget.onPick(
        tc,
        qty,
        comment.isEmpty ? null : comment,
        _course,
        _guest,
      );
      if (!mounted) return;
      setState(() {
        _selectedDish = null;
        _comment.clear();
        _search.clear();
      });
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = widget.loc;
    final lang = loc.currentLanguageCode;
    final h = MediaQuery.sizeOf(context).height * 0.85;

    return SafeArea(
      child: SizedBox(
        height: h,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      loc.t('pos_order_line_add'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: loc.t('close'),
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: loc.t('pos_order_line_search_hint'),
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'kitchen',
                  label: Text(loc.t('kitchen')),
                ),
                ButtonSegment(
                  value: 'bar',
                  label: Text(loc.t('bar')),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: widget.loading && widget.dishes.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _search.text.trim().isNotEmpty
                                  ? loc.t('no_results')
                                  : loc.t('pos_order_add_dish_empty_hint'),
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filtered.length,
                          itemBuilder: (ctx, i) {
                            final tc = _filtered[i];
                            final name = tc.dishNameLocalized?[lang]
                                        ?.trim()
                                        .isNotEmpty ==
                                    true
                                ? tc.dishNameLocalized![lang]!
                                : tc.dishName;
                            return ListTile(
                              title: Text(name),
                              subtitle: tc.sellingPrice != null
                                  ? Text(
                                      formatPosOrderMenuDue(
                                        ctx,
                                        tc.sellingPrice!,
                                      ),
                                    )
                                  : null,
                              onTap: () {
                                setState(() => _selectedDish = tc);
                              },
                            );
                          },
                        ),
            ),
            if (_selectedDish != null)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _selectedDish!.dishNameLocalized?[lang]
                                  ?.trim()
                                  .isNotEmpty ==
                              true
                          ? _selectedDish!.dishNameLocalized![lang]!
                          : _selectedDish!.dishName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      loc.t('pos_order_add_course_guest_hint'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                loc.t('pos_order_add_course_label'),
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              const SizedBox(height: 4),
                              DropdownButton<int>(
                                isExpanded: true,
                                value: _course.clamp(1, 8),
                                items: [
                                  for (var c = 1; c <= 8; c++)
                                    DropdownMenuItem(value: c, child: Text('$c')),
                                ],
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => _course = v);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                loc.t('pos_order_add_guest_label'),
                                style: Theme.of(context).textTheme.labelMedium,
                              ),
                              const SizedBox(height: 4),
                              DropdownButton<int?>(
                                isExpanded: true,
                                value: _guest,
                                items: [
                                  DropdownMenuItem<int?>(
                                    value: null,
                                    child: Text(loc.t('pos_order_add_guest_any')),
                                  ),
                                  for (var g = 1; g <= widget.guestCount; g++)
                                    DropdownMenuItem(
                                      value: g,
                                      child: Text(
                                        loc.t('pos_order_line_guest_short',
                                            args: {'n': '$g'}),
                                      ),
                                    ),
                                ],
                                onChanged: (v) => setState(() => _guest = v),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        SizedBox(
                          width: 130,
                          child: TextField(
                            controller: _qty,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                            ],
                            decoration: InputDecoration(
                              labelText: loc.t('pos_order_line_qty'),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _comment,
                            maxLines: 1,
                            decoration: InputDecoration(
                              labelText: loc.t('pos_order_line_comment'),
                              hintText: loc.t('pos_order_line_comment_hint'),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _adding ? null : () => _confirmAdd(loc),
                      icon: _adding
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_circle_outline),
                      label: Text(loc.t('pos_order_line_add')),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
