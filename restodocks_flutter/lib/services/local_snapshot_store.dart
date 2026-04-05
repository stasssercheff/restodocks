/// Локальное хранилище снимков данных (SQLite на iOS/Android/Desktop; web — no-op).
export 'local_snapshot_store_stub.dart'
    if (dart.library.io) 'local_snapshot_store_io.dart';
