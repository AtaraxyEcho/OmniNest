import 'package:drift/drift.dart';

import 'package:omninest/core/storage/tables/sync_operations.dart';
import 'package:omninest/core/storage/tables/cached_media_progress.dart';
import 'package:omninest/core/storage/tables/cached_reader_progress.dart';
import 'package:omninest/core/storage/tables/cached_reader_bookmarks.dart';
import 'package:omninest/core/storage/tables/cached_reader_annotations.dart';
import 'package:omninest/core/storage/tables/cached_reader_notes.dart';
import 'package:omninest/core/storage/tables/cached_reader_books.dart';
import 'package:omninest/core/storage/tables/cached_reader_chapters.dart';
import 'package:omninest/core/storage/tables/cached_reader_images.dart';
import 'package:omninest/core/storage/tables/app_backdrop_assets.dart';
import 'package:omninest/core/storage/tables/app_backdrop_settings.dart';
import 'package:omninest/core/storage/tables/sync_client_states.dart';
import 'package:omninest/core/storage/tables/sync_pending_invalidations.dart';
import 'package:omninest/core/storage/tables/sync_processed_events.dart';
import 'package:omninest/core/storage/local_database_connection.dart'
    if (dart.library.ffi) 'package:omninest/core/storage/local_database_connection_io.dart'
    if (dart.library.js_interop) 'package:omninest/core/storage/local_database_connection_web.dart'
    as connection;

part 'local_database.g.dart';

/// 本地 SQLite 数据库，用于离线缓存和同步队列
@DriftDatabase(
  tables: [
    SyncOperations,
    CachedMediaProgress,
    CachedReaderProgress,
    CachedReaderBookmarks,
    CachedReaderAnnotations,
    CachedReaderNotes,
    CachedReaderBooks,
    CachedReaderChapters,
    CachedReaderImages,
    AppBackdropAssets,
    AppBackdropSettingsTable,
    SyncClientStates,
    SyncPendingInvalidations,
    SyncProcessedEvents,
  ],
)
class LocalDatabase extends _$LocalDatabase {
  /// 创建本地数据库实例
  ///
  /// [executor] 可选的自定义查询执行器，用于测试时传入内存数据库
  LocalDatabase([QueryExecutor? executor])
    : super(executor ?? connection.openConnection());

  @override
  int get schemaVersion => 27;

  Future<bool> _tableExists(Migrator migrator, String tableName) async {
    final rows =
        await migrator.database
            .customSelect(
              'SELECT name FROM sqlite_master WHERE type = \'table\' AND name = ?',
              variables: [Variable.withString(tableName)],
            )
            .get();
    return rows.isNotEmpty;
  }

  Future<bool> _columnExists(
    Migrator migrator,
    String tableName,
    String columnName,
  ) async {
    final rows =
        await migrator.database
            .customSelect('PRAGMA table_info(\'$tableName\')')
            .get();
    return rows.any((row) => row.read<String>('name') == columnName);
  }

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onUpgrade: (migrator, from, to) async {
        if (from < 2) {
          await migrator.createTable(cachedReaderProgress);
        }
        if (from < 3) {
          await migrator.createTable(cachedReaderBookmarks);
        }
        if (from < 4) {
          await migrator.createTable(cachedReaderAnnotations);
          await migrator.createTable(cachedReaderNotes);
        }
        // Schema v5: cached_reader_progress 移除 chapter_id 列
        if (from < 5) {
          await migrator.deleteTable('cached_reader_progress');
          await migrator.createTable(cachedReaderProgress);
        }
        // Schema v6: 新增书籍元数据与章节内容缓存表（书籍详情表已在 v27 摘除）
        if (from < 6) {
          await migrator.createTable(cachedReaderBooks);
          await migrator.createTable(cachedReaderChapters);
        }
        // Schema v7: 新增章节图片 BLOB 缓存表
        if (from < 7) {
          await migrator.createTable(cachedReaderImages);
        }
        // Schema v8: cached_reader_progress 重新添加 chapter_id 列
        if (from < 8) {
          await migrator.database.customStatement(
            'ALTER TABLE cached_reader_progress ADD COLUMN chapter_id TEXT NOT NULL DEFAULT \'\'',
          );
        }
        // Schema v9: 主键改为 (itemId, chapterId)，支持多章节进度存储
        if (from < 9) {
          await migrator.database.customStatement(
            'DELETE FROM cached_reader_progress',
          );
          await migrator.deleteTable('cached_reader_progress');
          await migrator.createTable(cachedReaderProgress);
        }
        // Schema v10: 为漫画阅读补充稳定页面锚点字段
        if (from < 10) {
          await migrator.database.customStatement(
            'ALTER TABLE cached_reader_progress ADD COLUMN page_id TEXT',
          );
          await migrator.database.customStatement(
            'ALTER TABLE cached_reader_progress ADD COLUMN page_index INTEGER',
          );
          await migrator.database.customStatement(
            'ALTER TABLE cached_reader_progress ADD COLUMN page_fingerprint TEXT',
          );
          await migrator.database.customStatement(
            'ALTER TABLE cached_reader_progress ADD COLUMN source_id TEXT',
          );
          await migrator.database.customStatement(
            'ALTER TABLE cached_reader_progress ADD COLUMN manifest_version INTEGER',
          );
          await migrator.database.customStatement(
            'ALTER TABLE cached_reader_progress ADD COLUMN intra_page_offset REAL',
          );
        }
        // Schema v11: 为漫画进度补充跨 manifest 恢复锚点
        if (from < 11) {
          await migrator.database.customStatement(
            'ALTER TABLE cached_reader_progress ADD COLUMN source_page_index INTEGER',
          );
          await migrator.database.customStatement(
            'ALTER TABLE cached_reader_progress ADD COLUMN catalog_key TEXT',
          );
        }
        // Schema v12：新增桌面端本机背景库。
        if (from < 12) {
          await migrator.createTable(appBackdropAssets);
          await migrator.createTable(appBackdropSettingsTable);
        }
        // Schema v13：将 Portal 专属背景表原位迁移为应用级背景表。
        if (from >= 12 && from < 13) {
          if (await _tableExists(migrator, 'portal_local_backdrops') &&
              !await _tableExists(migrator, 'app_backdrop_assets')) {
            await migrator.database.customStatement(
              'ALTER TABLE portal_local_backdrops RENAME TO app_backdrop_assets',
            );
          }
          if (await _tableExists(migrator, 'portal_local_backdrop_settings') &&
              !await _tableExists(migrator, 'app_backdrop_settings')) {
            await migrator.database.customStatement(
              'ALTER TABLE portal_local_backdrop_settings RENAME TO app_backdrop_settings',
            );
          }
          if (await _tableExists(migrator, 'app_backdrop_settings')) {
            await migrator.database.customStatement(
              "UPDATE app_backdrop_settings SET id = 'application' WHERE id = 'digital_gallery'",
            );
          }
        }
        // Schema v14：背景库增加桌面端与移动端独立选择。
        if (from >= 12 && from < 14) {
          if (await _tableExists(migrator, 'app_backdrop_settings')) {
            if (!await _columnExists(
              migrator,
              'app_backdrop_settings',
              'separate_device_backdrops',
            )) {
              await migrator.database.customStatement(
                'ALTER TABLE app_backdrop_settings ADD COLUMN separate_device_backdrops INTEGER NOT NULL DEFAULT 0',
              );
            }
            if (!await _columnExists(
              migrator,
              'app_backdrop_settings',
              'desktop_backdrop_id',
            )) {
              await migrator.database.customStatement(
                'ALTER TABLE app_backdrop_settings ADD COLUMN desktop_backdrop_id TEXT',
              );
            }
            if (!await _columnExists(
              migrator,
              'app_backdrop_settings',
              'mobile_backdrop_id',
            )) {
              await migrator.database.customStatement(
                'ALTER TABLE app_backdrop_settings ADD COLUMN mobile_backdrop_id TEXT',
              );
            }
          }
        }
        // Schema v15：新增全平台实时同步游标、失效和事件去重表。
        if (from < 15) {
          await migrator.createTable(syncClientStates);
          await migrator.createTable(syncPendingInvalidations);
          await migrator.createTable(syncProcessedEvents);
        }
        // Schema v16：图片正文迁出 SQLite，并按用户建立加密文件索引。
        // 旧表没有用户归属字段，无法安全迁移，因此仅删除可重建的图片缓存。
        if (from < 16) {
          await migrator.deleteTable('cached_reader_images');
          await migrator.createTable(cachedReaderImages);
        }
        // Schema v17：阅读批注增加章节归属，避免章节内偏移跨章节串位。
        if (from < 17) {
          final annotationColumns =
              await migrator.database
                  .customSelect(
                    "PRAGMA table_info('cached_reader_annotations')",
                  )
                  .get();
          final hasChapterId = annotationColumns.any(
            (row) => row.read<String>('name') == 'chapter_id',
          );
          if (annotationColumns.isNotEmpty && !hasChapterId) {
            await migrator.database.customStatement(
              'ALTER TABLE cached_reader_annotations ADD COLUMN chapter_id TEXT',
            );
          }
        }
        // Schema v18：书籍元数据缓存增加版本指纹，服务端重解析后失效旧缓存。
        if (from < 18) {
          final bookColumns =
              await migrator.database
                  .customSelect("PRAGMA table_info('cached_reader_books')")
                  .get();
          final hasCacheVersion = bookColumns.any(
            (row) => row.read<String>('name') == 'cache_version',
          );
          if (bookColumns.isNotEmpty && !hasCacheVersion) {
            await migrator.database.customStatement(
              "ALTER TABLE cached_reader_books ADD COLUMN cache_version TEXT NOT NULL DEFAULT ''",
            );
          }
        }
        // Schema v19：背景库改为服务端事实来源,清理已退役的本机素材行。
        // 本机路径无法跨端表达,引用它们的选择会由归一化回落到内置壁纸。
        if (from >= 12 && from < 19) {
          if (await _tableExists(migrator, 'app_backdrop_assets')) {
            await migrator.database.customStatement(
              "DELETE FROM app_backdrop_assets WHERE source_type IN ('file', 'directory')",
            );
          }
        }
        // Schema v20：背景素材增加服务端生命周期状态,区分处理中/失效/缺失。
        if (from < 20) {
          if (await _tableExists(migrator, 'app_backdrop_assets') &&
              !await _columnExists(migrator, 'app_backdrop_assets', 'status')) {
            await migrator.database.customStatement(
              "ALTER TABLE app_backdrop_assets ADD COLUMN status TEXT NOT NULL DEFAULT 'READY'",
            );
          }
        }
        // Schema v21：背景设置增加 cover/fill 对齐锚点。
        if (from < 21) {
          if (await _tableExists(migrator, 'app_backdrop_settings') &&
              !await _columnExists(
                migrator,
                'app_backdrop_settings',
                'alignment',
              )) {
            await migrator.database.customStatement(
              "ALTER TABLE app_backdrop_settings ADD COLUMN alignment TEXT NOT NULL DEFAULT 'center'",
            );
          }
        }
        // Schema v22：背景素材记录服务端探测的视频编码与 Web 可播判定。
        if (from < 22) {
          if (await _tableExists(migrator, 'app_backdrop_assets') &&
              !await _columnExists(
                migrator,
                'app_backdrop_assets',
                'video_codec',
              )) {
            await migrator.database.customStatement(
              'ALTER TABLE app_backdrop_assets ADD COLUMN video_codec TEXT',
            );
            await migrator.database.customStatement(
              'ALTER TABLE app_backdrop_assets ADD COLUMN web_playable INTEGER NOT NULL DEFAULT 1',
            );
          }
        }
        // Schema v23：样式表改为书级池 + 章节次序引用，不再逐章重复携带正文里的那份
        // `<style>` 载体。旧行留默认值即可读：章节正文自带样式表时解析侧的内联通路
        // 照样生效，重解析后写入新形态。
        if (from < 23) {
          if (await _tableExists(migrator, 'cached_reader_books') &&
              !await _columnExists(
                migrator,
                'cached_reader_books',
                'stylesheet_pool_json',
              )) {
            await migrator.database.customStatement(
              "ALTER TABLE cached_reader_books ADD COLUMN stylesheet_pool_json TEXT NOT NULL DEFAULT '{}'",
            );
          }
          if (await _tableExists(migrator, 'cached_reader_chapters') &&
              !await _columnExists(
                migrator,
                'cached_reader_chapters',
                'stylesheet_refs_json',
              )) {
            await migrator.database.customStatement(
              "ALTER TABLE cached_reader_chapters ADD COLUMN stylesheet_refs_json TEXT NOT NULL DEFAULT '[]'",
            );
          }
        }
        // Schema v24：进度行补全书比例，并把账号归属纳入主键；书签/批注/笔记与
        // 同步队列补归属列。SQLite 不能原地改主键，进度表按重命名-建新表-回填搬迁；
        // 旧行没有归属可判，原样搬入并保持空归属，由后续写入自然覆盖。
        if (from < 24) {
          if (await _tableExists(migrator, 'cached_reader_progress')) {
            await migrator.database.customStatement(
              'ALTER TABLE cached_reader_progress '
              'RENAME TO cached_reader_progress_v23',
            );
            await migrator.createTable(cachedReaderProgress);
            await migrator.database.customStatement(
              'INSERT INTO cached_reader_progress '
              '(user_id, item_id, chapter_id, char_offset, chapter_progress, '
              ' book_progress, mode, page_id, page_index, page_fingerprint, '
              ' source_id, source_page_index, catalog_key, manifest_version, '
              ' intra_page_offset, updated_at) '
              "SELECT '', item_id, chapter_id, char_offset, chapter_progress, "
              ' NULL, mode, page_id, page_index, page_fingerprint, '
              ' source_id, source_page_index, catalog_key, manifest_version, '
              ' intra_page_offset, updated_at '
              'FROM cached_reader_progress_v23',
            );
            await migrator.database.customStatement(
              'DROP TABLE cached_reader_progress_v23',
            );
          }
          for (final tableName in const [
            'cached_reader_bookmarks',
            'cached_reader_annotations',
            'cached_reader_notes',
            'sync_operations',
          ]) {
            if (await _tableExists(migrator, tableName) &&
                !await _columnExists(migrator, tableName, 'user_id')) {
              await migrator.database.customStatement(
                "ALTER TABLE $tableName ADD COLUMN user_id TEXT NOT NULL DEFAULT ''",
              );
            }
          }
        }
        // Schema v25：书签补章节归属。偏移是章内的，缺归属时详情页只能跳回
        // 当前进度章；旧行无从判断归属，保持 NULL 由跳转侧按偏移退化处理。
        if (from < 25) {
          if (await _tableExists(migrator, 'cached_reader_bookmarks') &&
              !await _columnExists(
                migrator,
                'cached_reader_bookmarks',
                'chapter_id',
              )) {
            await migrator.database.customStatement(
              'ALTER TABLE cached_reader_bookmarks ADD COLUMN chapter_id TEXT',
            );
          }
        }
        // Schema v26：书籍元数据与章节切片缓存把归属账号纳入主键。这两张表的正文、
        // 样式表池与次序用当前登录用户的密钥加密，共享书籍在不同账号下复用同一个
        // itemId，不归户就会让换号后的账号命中上一个账号的密文并解密失败。
        // SQLite 不能原地改主键，按重命名-建新表-回填搬迁；旧行没有归属可判，
        // 原样搬入并保持空归属，由后续写入自然覆盖。
        if (from < 26) {
          if (await _tableExists(migrator, 'cached_reader_books')) {
            await migrator.database.customStatement(
              'ALTER TABLE cached_reader_books RENAME TO cached_reader_books_v25',
            );
            await migrator.createTable(cachedReaderBooks);
            await migrator.database.customStatement(
              'INSERT INTO cached_reader_books '
              '(user_id, item_id, title, author, description, publisher, '
              ' language, chapters_json, stylesheet_pool_json, total_chars, '
              ' item_type, cache_version, cached_at) '
              "SELECT '', item_id, title, author, description, publisher, "
              ' language, chapters_json, stylesheet_pool_json, total_chars, '
              ' item_type, cache_version, cached_at '
              'FROM cached_reader_books_v25',
            );
            await migrator.database.customStatement(
              'DROP TABLE cached_reader_books_v25',
            );
          }
          if (await _tableExists(migrator, 'cached_reader_chapters')) {
            await migrator.database.customStatement(
              'ALTER TABLE cached_reader_chapters '
              'RENAME TO cached_reader_chapters_v25',
            );
            await migrator.createTable(cachedReaderChapters);
            await migrator.database.customStatement(
              'INSERT INTO cached_reader_chapters '
              '(user_id, item_id, content_path, title, chapter_number, '
              ' char_count, processed_html, stylesheet_refs_json, cached_at) '
              "SELECT '', item_id, content_path, title, chapter_number, "
              ' char_count, processed_html, stylesheet_refs_json, cached_at '
              'FROM cached_reader_chapters_v25',
            );
            await migrator.database.customStatement(
              'DROP TABLE cached_reader_chapters_v25',
            );
          }
        }
        // Schema v27：摘除从未接线、也没有归属列的两张缓存表。
        // cached_files 的唯一写入者 OfflineCacheService 没有生产调用点，离线文件与
        // 加密图片缓存早已由 LocalBookCache / cached_reader_images 按账号承接；
        // cached_reader_book_details 只剩一句删除，实时详情一直直接走接口。
        if (from < 27) {
          await migrator.database.customStatement(
            'DROP TABLE IF EXISTS cached_files',
          );
          await migrator.database.customStatement(
            'DROP TABLE IF EXISTS cached_reader_book_details',
          );
        }
      },
    );
  }

  /// 清理退出账号关联的本地敏感数据，保留设备级背景设置。
  ///
  /// 带归属列的表按「当前账号 + 设备级空归属」两类删除：同设备上另一个具名账号
  /// 尚未同步的进度、批注与队列必须原样留下，退出谁就清谁。整表清空等于让 A 的
  /// 退出把 B 的离线写入一并删掉。
  ///
  /// [cachedMediaProgress] 没有归属列（按 mediaId 存的服务端只读快照），只能整表清。
  Future<void> clearUserData(String userId) {
    return transaction(() async {
      final owned = [userId, ''];
      await (delete(syncOperations)
        ..where((table) => table.userId.isIn(owned))).go();
      await delete(cachedMediaProgress).go();
      await (delete(cachedReaderProgress)
        ..where((table) => table.userId.isIn(owned))).go();
      await (delete(cachedReaderBookmarks)
        ..where((table) => table.userId.isIn(owned))).go();
      await (delete(cachedReaderAnnotations)
        ..where((table) => table.userId.isIn(owned))).go();
      await (delete(cachedReaderNotes)
        ..where((table) => table.userId.isIn(owned))).go();
      await (delete(cachedReaderBooks)
        ..where((table) => table.userId.isIn(owned))).go();
      await (delete(cachedReaderChapters)
        ..where((table) => table.userId.isIn(owned))).go();
      await (delete(cachedReaderImages)
        ..where((table) => table.userId.equals(userId))).go();
      await (delete(syncClientStates)
        ..where((table) => table.userId.equals(userId))).go();
      await (delete(syncPendingInvalidations)
        ..where((table) => table.userId.equals(userId))).go();
      await (delete(syncProcessedEvents)
        ..where((table) => table.userId.equals(userId))).go();
    });
  }
}
