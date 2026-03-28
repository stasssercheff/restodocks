/// Строка заказа зала (pos_order_lines).
class PosOrderLine {
  const PosOrderLine({
    required this.id,
    required this.orderId,
    required this.techCardId,
    required this.quantity,
    required this.courseNumber,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.comment,
    this.guestNumber,
    this.dishName,
    this.dishNameLocalized,
    this.sellingPrice,
    this.techCardDepartment,
    this.techCardCategory,
    this.techCardSections = const [],
    this.servedAt,
  });

  final String id;
  final String orderId;
  final String techCardId;
  final double quantity;
  final String? comment;
  final int courseNumber;
  final int? guestNumber;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Из embed tech_cards (для отображения без второго запроса).
  final String? dishName;
  final Map<String, String>? dishNameLocalized;
  final double? sellingPrice;
  final String? techCardDepartment;

  /// Категория и секции ТТК (для маршрутизации кухня/бар).
  final String? techCardCategory;
  final List<String> techCardSections;

  /// Когда блюдо отдано гостю (после отправки заказа).
  final DateTime? servedAt;

  factory PosOrderLine.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? tc;
    final embed = json['tech_cards'];
    if (embed is Map<String, dynamic>) {
      tc = embed;
    } else if (embed is List && embed.isNotEmpty && embed.first is Map) {
      tc = Map<String, dynamic>.from(embed.first as Map);
    }

    Map<String, String>? locMap;
    final loc = tc?['dish_name_localized'];
    if (loc is Map<String, dynamic>) {
      locMap = loc.map((k, v) => MapEntry(k, v.toString()));
    }

    final secRaw = tc?['sections'];
    final sections = secRaw is List
        ? secRaw.map((e) => e.toString()).toList()
        : <String>[];

    final servedRaw = json['served_at'];
    DateTime? servedAt;
    if (servedRaw != null) {
      servedAt = DateTime.tryParse(servedRaw.toString());
    }

    return PosOrderLine(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      techCardId: json['tech_card_id'] as String,
      quantity: (json['quantity'] as num).toDouble(),
      comment: json['comment'] as String?,
      courseNumber: (json['course_number'] as num?)?.toInt() ?? 1,
      guestNumber: (json['guest_number'] as num?)?.toInt(),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      dishName: tc?['dish_name'] as String?,
      dishNameLocalized: locMap,
      sellingPrice: (tc?['selling_price'] as num?)?.toDouble(),
      techCardDepartment: tc?['department'] as String?,
      techCardCategory: tc?['category'] as String?,
      techCardSections: sections,
      servedAt: servedAt,
    );
  }

  String dishTitleForLang(String langCode) {
    final loc = dishNameLocalized;
    if (loc != null && loc[langCode]?.trim().isNotEmpty == true) {
      return loc[langCode]!.trim();
    }
    if (loc != null && loc['ru']?.trim().isNotEmpty == true) {
      return loc['ru']!.trim();
    }
    final base = dishName?.trim();
    if (base != null && base.isNotEmpty) return base;
    return '—';
  }
}
