/// Ссылка на экран/сущность приложения во вложении к сообщению.
class EmployeeMessageSystemLink {
  const EmployeeMessageSystemLink({
    required this.kind,
    required this.path,
    required this.label,
  });

  /// Короткий код типа (ttk, inbox_inv, menu, …).
  final String kind;
  final String path;
  final String label;

  Map<String, dynamic> toJson() => {
        'k': kind,
        'p': path,
        't': label,
      };

  factory EmployeeMessageSystemLink.fromJson(Map<String, dynamic> json) {
    return EmployeeMessageSystemLink(
      kind: (json['k'] ?? json['kind'] ?? '').toString(),
      path: (json['p'] ?? json['path'] ?? '').toString(),
      label: (json['t'] ?? json['label'] ?? '').toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmployeeMessageSystemLink &&
          runtimeType == other.runtimeType &&
          path == other.path;

  @override
  int get hashCode => path.hashCode;
}
