import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Дублирование крупных JSON-снимков на диске (помимо SharedPreferences).
class LocalSnapshotStore {
  LocalSnapshotStore._();
  static final LocalSnapshotStore instance = LocalSnapshotStore._();

  Database? _db;

  Future<Database> _database() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/restodocks_local_snapshots.db';
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE snapshots (
            scope TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  Future<void> put(String scope, String payload) async {
    final db = await _database();
    await db.insert(
      'snapshots',
      {
        'scope': scope,
        'payload': payload,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Сырой JSON снимка или `null`, если ключа нет.
  Future<String?> get(String scope) async {
    final db = await _database();
    final rows = await db.query(
      'snapshots',
      columns: ['payload'],
      where: 'scope = ?',
      whereArgs: [scope],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['payload'] as String?;
  }

  Future<void> clearEstablishment(String establishmentId) async {
    final db = await _database();
    await db.delete(
      'snapshots',
      where: 'scope LIKE ?',
      whereArgs: ['$establishmentId:%'],
    );
  }

  Future<void> clearAll() async {
    final db = await _database();
    await db.delete('snapshots');
  }
}
