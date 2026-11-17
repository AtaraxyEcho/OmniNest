import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/reader/data/reader_local_storage.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// 摘要：v24 的真库升级到"归属进主键 + 书签带章节"那份形态时，旧行必须搬得过来。
///
/// SQLite 不能原地改主键，v26 只能按重命名-建新表-回填搬迁；列名或顺序写错时，
/// 新建库上的单测一律看不见（新库直接按最新 schema 建表），只有拿一份真的旧文件
/// 升级才会撞出来——而这条路径正是桌面端换版本后第一次打开阅读器要走的路。
void main() {
  Future<LocalDatabase> openMigrated() async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'reader-cache-migration-',
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
    legacy.execute(
      'CREATE TABLE cached_reader_bookmarks ('
      'id TEXT PRIMARY KEY, '
      "user_id TEXT NOT NULL DEFAULT '', "
      'reader_item_id TEXT NOT NULL, '
      'char_offset INTEGER NOT NULL DEFAULT 0, '
      'progress_percent REAL NOT NULL DEFAULT 0, '
      'note TEXT, '
      'created_at INTEGER NOT NULL)',
    );
    legacy.execute(
      'INSERT INTO cached_reader_bookmarks '
      '(id, user_id, reader_item_id, '
      'char_offset, progress_percent, created_at) '
      "VALUES ('bm-1', '', 'book-1', 640, 0.4, 1780000000000)",
    );
    legacy.execute(
      'CREATE TABLE cached_reader_books ('
      'item_id TEXT PRIMARY KEY, '
      'title TEXT, author TEXT, description TEXT, publisher TEXT, '
      'language TEXT, '
      "chapters_json TEXT NOT NULL DEFAULT '[]', "
      "stylesheet_pool_json TEXT NOT NULL DEFAULT '{}', "
      'total_chars INTEGER NOT NULL DEFAULT 0, '
      "item_type TEXT NOT NULL DEFAULT 'EPUB', "
      "cache_version TEXT NOT NULL DEFAULT '', "
      'cached_at INTEGER NOT NULL)',
    );
    legacy.execute(
      'INSERT INTO cached_reader_books (item_id, title, chapters_json, '
      'stylesheet_pool_json, total_chars, item_type, cache_version, cached_at) '
      "VALUES ('book-1', '测试书', '[]', '{\"a.css\":\"p {}\"}', 1200, "
      "'EPUB', 'v1', 1780000000000)",
    );
    legacy.execute(
      'CREATE TABLE cached_reader_chapters ('
      'item_id TEXT NOT NULL, content_path TEXT NOT NULL, '
      "title TEXT NOT NULL DEFAULT '', "
      'chapter_number INTEGER NOT NULL DEFAULT 0, '
      'char_count INTEGER NOT NULL DEFAULT 0, '
      'processed_html TEXT NOT NULL, '
      "stylesheet_refs_json TEXT NOT NULL DEFAULT '[]', "
      'cached_at INTEGER NOT NULL, '
      'PRIMARY KEY (item_id, content_path))',
    );
    legacy.execute(
      'INSERT INTO cached_reader_chapters (item_id, content_path, title, '
      'chapter_number, char_count, processed_html, cached_at) '
      "VALUES ('book-1', 'OEBPS/ch1.xhtml', '第一章', 1, 24, "
      "'<html><body><p>正文一段</p></body></html>', 1780000000000)",
    );
    legacy.userVersion = 24;
    legacy.close();

    final migrated = LocalDatabase(NativeDatabase(databaseFile));
    addTearDown(migrated.close);
    return migrated;
  }

  test('书签补章节列，旧行不丢', () async {
    final migrated = await openMigrated();

    expect(
      await _columnNames(migrated, 'cached_reader_bookmarks'),
      contains('chapter_id'),
    );

    final bookmarks = await ReaderLocalStorage(
      migrated,
    ).loadBookmarks('book-1');
    expect(bookmarks, hasLength(1));
    expect(bookmarks.single.charOffset, 640);
    expect(bookmarks.single.chapterId, isNull, reason: '旧行无从判断归属章节');

    expect(await _userVersion(migrated), migrated.schemaVersion);
  });

  test('元数据与章节切片搬到带归属的新主键后仍读得到', () async {
    final migrated = await openMigrated();

    expect(
      await _tableNames(migrated),
      isNot(contains('cached_reader_books_v25')),
    );
    expect(
      await _tableNames(migrated),
      isNot(contains('cached_reader_chapters_v25')),
    );
    final bookColumns = await _columnNames(migrated, 'cached_reader_books');
    final chapterColumns = await _columnNames(
      migrated,
      'cached_reader_chapters',
    );
    expect(bookColumns, contains('user_id'));
    expect(chapterColumns, contains('user_id'));

    // 旧行保持空归属：无会话读取（web/未登录口径）必须还能看见它。
    final legacyStore = ReaderLocalStorage(migrated);
    expect(await legacyStore.loadBookMeta('book-1'), isNotNull);
    expect(
      await legacyStore.loadChapterContent(
        itemId: 'book-1',
        contentPath: 'OEBPS/ch1.xhtml',
      ),
      isNotNull,
    );

    // 归属进主键的落点：换号写同一本书不得顶掉上一个账号的那份。
    final alice = ReaderLocalStorage(migrated, userId: 'alice');
    await alice.saveBookMeta(
      itemId: 'book-1',
      title: '爱丽丝的书',
      chaptersJson: '[]',
      totalChars: 10,
      itemType: 'EPUB',
    );
    await alice.saveChapterContent(
      itemId: 'book-1',
      contentPath: 'OEBPS/ch1.xhtml',
      title: '第一章',
      chapterNumber: 1,
      charCount: 24,
      processedHtml: '<html><body><p>新正文</p></body></html>',
      stylesheetRefs: const <String>[],
    );
    expect((await alice.loadBookMeta('book-1'))?['title'], '爱丽丝的书');
    expect(await legacyStore.loadBookMeta('book-1'), isNotNull);

    final rows = await migrated.select(migrated.cachedReaderChapters).get();
    expect(rows, hasLength(2));
  });

  test('书签按章节归属写入后可原样读回', () async {
    final migrated = await openMigrated();
    final store = ReaderLocalStorage(migrated, userId: 'alice');
    final createdAt = DateTime(2026, 10, 16);

    await store.saveBookmark(
      ReaderBookmark(
        id: 'bm-new',
        readerItemId: 'book-1',
        chapterId: 't1280',
        charOffset: 640,
        progressPercent: 0.4,
        createdAt: createdAt,
      ),
    );

    final stored = await store.loadBookmarkById('bm-new');
    expect(stored?.chapterId, 't1280');
    expect(stored?.charOffset, 640);
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
