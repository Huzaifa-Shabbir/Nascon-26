import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LocalDb {
  Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, 'nascon.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cache (
            key TEXT PRIMARY KEY,
            json TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE pending_actions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id TEXT NOT NULL,
            action_id TEXT NOT NULL UNIQUE,
            type TEXT NOT NULL,
            payload TEXT NOT NULL,
            base_version INTEGER NOT NULL DEFAULT 0,
            queued_at TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending'
          )
        ''');
        await db.execute('''
          CREATE TABLE kv (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }

  Future<void> putCache(String key, Object data) async {
    final d = await db;
    await d.insert(
      'cache',
      {
        'key': key,
        'json': jsonEncode(data),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<dynamic> getCache(String key) async {
    final d = await db;
    final rows = await d.query('cache', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['json'] as String);
  }

  Future<void> setKv(String key, String value) async {
    final d = await db;
    await d.insert(
      'kv',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getKv(String key) async {
    final d = await db;
    final rows = await d.query('kv', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  Future<void> enqueueAction({
    required String deviceId,
    required String actionId,
    required String type,
    required Map<String, dynamic> payload,
    required int baseVersion,
    required String queuedAt,
  }) async {
    final d = await db;
    await d.insert(
      'pending_actions',
      {
        'device_id': deviceId,
        'action_id': actionId,
        'type': type,
        'payload': jsonEncode(payload),
        'base_version': baseVersion,
        'queued_at': queuedAt,
        'status': 'pending',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> pendingActions() async {
    final d = await db;
    final rows = await d.query(
      'pending_actions',
      where: "status = 'pending'",
      orderBy: 'queued_at ASC, id ASC',
    );
    return rows.map((r) {
      return {
        ...r,
        'payload': jsonDecode(r['payload'] as String),
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> allActions() async {
    final d = await db;
    final rows = await d.query('pending_actions', orderBy: 'queued_at DESC, id DESC');
    return rows.map((r) {
      return {
        ...r,
        'payload': jsonDecode(r['payload'] as String),
      };
    }).toList();
  }

  Future<void> markDone(String actionId, {String status = 'synced'}) async {
    final d = await db;
    await d.update(
      'pending_actions',
      {'status': status},
      where: 'action_id = ?',
      whereArgs: [actionId],
    );
  }

  Future<void> clearSynced() async {
    final d = await db;
    await d.delete('pending_actions', where: "status != 'pending'");
  }

  Future<int> pendingCount() async {
    final d = await db;
    final r = await d.rawQuery(
      "SELECT COUNT(*) AS c FROM pending_actions WHERE status = 'pending'",
    );
    return (r.first['c'] as int?) ?? 0;
  }
}
