/// Web: SQLite недоступен — снимки только в SharedPreferences через OfflineCacheService.
class LocalSnapshotStore {
  LocalSnapshotStore._();
  static final LocalSnapshotStore instance = LocalSnapshotStore._();

  Future<void> put(String scope, String payload) async {}

  Future<void> clearEstablishment(String establishmentId) async {}

  Future<void> clearAll() async {}
}
