import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/reader/data/reader_local_progress.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// 摘要：v23 的进度表在真库上升级到"归属进主键"的那份形态时，旧行必须搬得过来。
///
/// SQLite 不能原地改主键，v24 只能按重命名-建新表-回填搬迁；列名或顺序写错时，
/// 新建库上的单测一律看不见（新库直接按 v24 建表），只有拿一份真的 v23 文件升级
/// 才会撞出来——而这条路径正是桌面端换版本后第一次打开阅读器要走的路。
void main() {
  test('旧进度表升级后保留位置，且归属进主键后两账号各存一条', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'reader-progress-migration-',
    );
    final databaseFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}legacy.sqlite',
    );
    addTearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    final legacy = sqlite.sqlite3.open(databaseFile.path);
    legacy.execute('''
      CREATE TABLE cached_reader_progress (
        item_id TEXT NOT NULL,
        chapter_id TEXT NOT NULL DEFAULT '',
        char_offset INTEGER NOT NULL DEFAULT 0,
        chapter_progress REAL NOT NULL DEFAULT 0,
        mode TEXT NOT NULL DEFAULT 'scroll',
        page_id TEXT,
        page_index INTEGER,
        page_fingerprint TEXT,
        source_id TEXT,
        source_page_index INTEGER,
        catalog_key TEXT,
        manifest_version INTEGER,
        intra_page_offset REAL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (item_id, chapter_id)
      )
    ''');
    legacy.execute('''
      INSERT INTO cached_reader_progress (
        item_id, chapter_id, char_offset, chapter_progress, mode, updated_at
      ) VALUES (
        'book-1', 'chapter-10', 4242, 0, 'scroll', 1780000000000
      )
    ''');
    legacy.execute(
      'CREATE TABLE cached_reader_bookmarks ('
      'id TEXT PRIMARY KEY, item_id TEXT NOT NULL)',
    );
    legacy.execute(
      'CREATE TABLE sync_operations ('
      'id TEXT PRIMARY KEY, type TEXT NOT NULL, payload TEXT NOT NULL, '
      "status TEXT NOT NULL DEFAULT 'pending')",
    );
    legacy.userVersion = 23;
    legacy.close();

    final migrated = LocalDatabase(NativeDatabase(databaseFile));
    addTearDown(migrated.close);

    final deviceOwner = DatabaseReaderLocalProgressStore(migrated);
    final payload = await deviceOwner.load('book-1', 'chapter-10');
    expect(payload, isNotNull, reason: '旧行没搬进新表，升级等于把进度清空');
    expect(payload!['charOffset'], 4242);
    expect(payload['bookProgress'], isNull, reason: '旧行没有全书比例，回填必须是空值');
    expect(payload['updatedAt'], isNotNull, reason: '搬迁后的记录时刻要还能读出来');

    // 归属进主键的落点：同设备换号写同一章，不得顶掉上一个账号尚未补传的那条。
    final otherAccount = DatabaseReaderLocalProgressStore(
      migrated,
      userId: 'user-b',
    );
    await otherAccount.save(
      itemId: 'book-1',
      chapterId: 'chapter-10',
      charOffset: 99,
      chapterProgress: 0,
      mode: 'scroll',
      updatedAt: DateTime(2026, 6, 2),
    );
    expect(
      (await deviceOwner.load('book-1', 'chapter-10'))?['charOffset'],
      4242,
    );
    expect(
      (await otherAccount.load('book-1', 'chapter-10'))?['charOffset'],
      99,
    );

    expect(
      await _tableNames(migrated),
      isNot(contains('cached_reader_progress_v23')),
    );
    expect(
      await _columnNames(migrated, 'cached_reader_bookmarks'),
      contains('user_id'),
    );
    expect(
      await _columnNames(migrated, 'sync_operations'),
      contains('user_id'),
    );
    expect(await _userVersion(migrated), migrated.schemaVersion);
  });
}

Future<List<String>> _tableNames(LocalDatabase database) async {
  final rows =
      await database
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .get();
  return rows.map((row) => row.read<String>('name')).toList(growable: false);
}

Future<List<String>> _columnNames(LocalDatabase database, String table) async {
  final rows = await database.customSelect("PRAGMA table_info('$table')").get();
  return rows.map((row) => row.read<String>('name')).toList(growable: false);
}

Future<int> _userVersion(LocalDatabase database) async {
  final row = await database.customSelect('PRAGMA user_version').getSingle();
  return row.read<int>('user_version');
}
