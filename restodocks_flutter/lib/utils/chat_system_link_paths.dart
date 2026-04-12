import '../models/employee_message_system_link.dart';
import '../models/inbox_document.dart';
import '../services/localization_service.dart';

const int kMaxSystemLinksPerMessage = 8;

/// Пути, которые разрешено сохранять во вложении (генерируются только из приложения).
bool isAllowedInternalChatPath(String path) {
  final p = path.trim();
  if (!p.startsWith('/') || p.contains('..')) return false;
  const prefixes = <String>[
    '/inbox/',
    '/menu/',
    '/schedule/',
    '/tech-cards/',
    '/product-order',
    '/procurement-receipt',
    '/checklists/',
  ];
  return prefixes.any((pre) => p.startsWith(pre));
}

List<EmployeeMessageSystemLink> sanitizeSystemLinks(List<EmployeeMessageSystemLink>? raw) {
  if (raw == null || raw.isEmpty) return [];
  final out = <EmployeeMessageSystemLink>[];
  final seen = <String>{};
  for (final l in raw) {
    if (out.length >= kMaxSystemLinksPerMessage) break;
    if (l.path.isEmpty || l.label.isEmpty) continue;
    if (!isAllowedInternalChatPath(l.path)) continue;
    if (seen.contains(l.path)) continue;
    seen.add(l.path);
    out.add(l);
  }
  return out;
}

/// Ссылка из документа «Входящие» (если тип поддерживается).
EmployeeMessageSystemLink? chatLinkFromInboxDocument(
  InboxDocument d,
  LocalizationService loc,
) {
  switch (d.type) {
    case DocumentType.inventory:
      return EmployeeMessageSystemLink(
        kind: 'inbox_inv',
        path: '/inbox/inventory/${d.id}',
        label: d.getLocalizedTitle(loc),
      );
    case DocumentType.iikoInventory:
      return EmployeeMessageSystemLink(
        kind: 'inbox_iiko',
        path: '/inbox/iiko/${d.id}',
        label: d.getLocalizedTitle(loc),
      );
    case DocumentType.productOrder:
      return EmployeeMessageSystemLink(
        kind: 'inbox_order',
        path: '/inbox/order/${d.id}',
        label: d.getLocalizedTitle(loc),
      );
    case DocumentType.checklistSubmission:
    case DocumentType.checklistMissedDeadline:
      return EmployeeMessageSystemLink(
        kind: 'inbox_checklist',
        path: '/inbox/checklist/${d.id}',
        label: d.getLocalizedTitle(loc),
      );
    case DocumentType.writeoff:
      return EmployeeMessageSystemLink(
        kind: 'inbox_writeoff',
        path: '/inbox/writeoff/${d.id}',
        label: d.getLocalizedTitle(loc),
      );
    case DocumentType.techCardChangeRequest:
      return EmployeeMessageSystemLink(
        kind: 'inbox_ttk_change',
        path: '/inbox/ttk-change/${d.id}',
        label: d.getLocalizedTitle(loc),
      );
    case DocumentType.procurementGoodsReceipt:
      return EmployeeMessageSystemLink(
        kind: 'inbox_receipt',
        path: '/inbox/procurement-receipt/${d.id}',
        label: d.getLocalizedTitle(loc),
      );
    case DocumentType.procurementPriceApproval:
      return EmployeeMessageSystemLink(
        kind: 'inbox_price_appr',
        path: '/inbox/procurement-price-approval/${d.id}',
        label: d.getLocalizedTitle(loc),
      );
    case DocumentType.shiftConfirmation:
      return null;
  }
}
