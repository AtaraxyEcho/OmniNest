import 'package:drift/drift.dart';

import 'package:omninest/core/storage/tables/cached_files.dart';
import 'package:omninest/core/storage/tables/sync_operations.dart';
import 'package:omninest/core/storage/tables/cached_media_progress.dart';
import 'package:omninest/core/storage/tables/cached_reader_progress.dart';
import 'package:omninest/core/storage/tables/cached_reader_bookmarks.dart';
import 'package:omninest/core/storage/tables/cached_reader_annotations.dart';
import 'package:omninest/core/storage/tables/cached_reader_notes.dart';
import 'package:omninest/core/storage/tables/cached_reader_books.dart';
import 'package:omninest/core/storage/tables/cached_reader_chapters.dart';
import 'package:omninest/core/storage/tables/cached_reader_book_details.dart';
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
    CachedFiles,
    SyncOperations,
    CachedMediaProgress,
    CachedReaderProgress,
    CachedReaderBookmarks,
    CachedReaderAnnotations,
    CachedReaderNotes,
    CachedReaderBooks,
    CachedReaderChapters,
    CachedReaderBookDetails,
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
  int get schemaVersion => 20;

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
        // Schema v6: 新增书籍元数据、章节内容、书籍详情缓存表
        if (from < 6) {
          await migrator.createTable(cachedReaderBooks);
          await migrator.createTable(cachedReaderChapters);
          await migrator.createTable(cachedReaderBookDetails);
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
          await migrator.database.customStatement(
            'ALTER TABLE portal_local_backdrops RENAME TO app_backdrop_assets',
          );
          await migrator.database.customStatement(
            'ALTER TABLE portal_local_backdrop_settings RENAME TO app_backdrop_settings',
          );
          await migrator.database.customStatement(
            "UPDATE app_backdrop_settings SET id = 'application' WHERE id = 'digital_gallery'",
          );
        }
        // Schema v14：背景库增加桌面端与移动端独立选择。
        if (from >= 12 && from < 14) {
          await migrator.database.customStatement(
            'ALTER TABLE app_backdrop_settings ADD COLUMN separate_device_backdrops INTEGER NOT NULL DEFAULT 0',
          );
          await migrator.database.customStatement(
            'ALTER TABLE app_backdrop_settings ADD COLUMN desktop_backdrop_id TEXT',
          );
          await migrator.database.customStatement(
            'ALTER TABLE app_backdrop_settings ADD COLUMN mobile_backdrop_id TEXT',
          );
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
          await migrator.database.customStatement(
            "DELETE FROM app_backdrop_assets WHERE source_type IN ('file', 'directory')",
          );
        }
        // Schema v20：背景素材增加服务端生命周期状态,区分处理中/失效/缺失。
        if (from < 20) {
          final backdropColumns =
              await migrator.database
                  .customSelect("PRAGMA table_info('app_backdrop_assets')")
                  .get();
          final hasStatus = backdropColumns.any(
            (row) => row.read<String>('name') == 'status',
          );
          if (backdropColumns.isNotEmpty && !hasStatus) {
            await migrator.database.customStatement(
              "ALTER TABLE app_backdrop_assets ADD COLUMN status TEXT NOT NULL DEFAULT 'READY'",
            );
          }
        }
      },
    );
  }

  /// 清理退出账号关联的本地敏感数据，保留设备级背景设置。
  Future<void> clearUserData(String userId) {
    return transaction(() async {
      await delete(syncOperations).go();
      await delete(cachedFiles).go();
      await delete(cachedMediaProgress).go();
      await delete(cachedReaderProgress).go();
      await delete(cachedReaderBookmarks).go();
      await delete(cachedReaderAnnotations).go();
      await delete(cachedReaderNotes).go();
      await delete(cachedReaderBooks).go();
      await delete(cachedReaderChapters).go();
      await delete(cachedReaderBookDetails).go();
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
