import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  late LocalDatabase db;
  late bool dbOpen;

  setUp(() {
    db = LocalDatabase(NativeDatabase.memory());
    dbOpen = true;
  });

  tearDown(() async {
    if (dbOpen) {
      await db.close();
    }
  });

  test('cachedFiles table stores and retrieves file metadata', () async {
    await db
        .into(db.cachedFiles)
        .insert(
          CachedFilesCompanion.insert(
            id: 'file-1',
            fileName: 'test.pdf',
            sizeBytes: 1024,
            cachedAt: DateTime(2026, 6, 5),
          ),
        );
    final files = await db.select(db.cachedFiles).get();
    expect(files, hasLength(1));
    expect(files.first.fileName, 'test.pdf');
    expect(files.first.sizeBytes, 1024);
  });

  test('syncOperations table stores pending operations', () async {
    await db
        .into(db.syncOperations)
        .insert(
          SyncOperationsCompanion.insert(
            type: 'file.favorite',
            payload: '{"fileId": "abc"}',
            createdAt: DateTime(2026, 6, 5),
          ),
        );
    final ops = await db.select(db.syncOperations).get();
    expect(ops, hasLength(1));
    expect(ops.first.type, 'file.favorite');
    expect(ops.first.status, 'pending');
  });

  test('cachedMediaProgress table stores playback position', () async {
    await db
        .into(db.cachedMediaProgress)
        .insert(
          CachedMediaProgressCompanion.insert(
            mediaId: 'movie-1',
            mediaType: 'video',
            progressPercent: 45.5,
            positionSeconds: 1200,
            durationSeconds: 7200,
            updatedAt: DateTime(2026, 6, 5),
          ),
        );
    final progress = await db.select(db.cachedMediaProgress).get();
    expect(progress, hasLength(1));
    expect(progress.first.progressPercent, 45.5);
  });

  test('cachedReaderProgress table stores reading position', () async {
    await db
        .into(db.cachedReaderProgress)
        .insert(
          CachedReaderProgressCompanion.insert(
            itemId: 'book-1',
            charOffset: const Value(2400),
            chapterProgress: const Value(0.8),
            mode: const Value('scroll'),
            pageId: const Value('page-1'),
            pageIndex: const Value(12),
            pageFingerprint: const Value('fingerprint-1'),
            sourceId: const Value('source-1'),
            sourcePageIndex: const Value(4),
            catalogKey: const Value('volume-1/chapter-4'),
            manifestVersion: const Value(3),
            intraPageOffset: const Value(0.4),
            updatedAt: DateTime(2026, 6, 12),
          ),
        );

    final progress = await db.select(db.cachedReaderProgress).get();

    expect(progress, hasLength(1));
    expect(progress.first.charOffset, 2400);
    expect(progress.first.chapterProgress, 0.8);
    expect(progress.first.pageId, 'page-1');
    expect(progress.first.pageIndex, 12);
    expect(progress.first.pageFingerprint, 'fingerprint-1');
    expect(progress.first.sourceId, 'source-1');
    expect(progress.first.sourcePageIndex, 4);
    expect(progress.first.catalogKey, 'volume-1/chapter-4');
    expect(progress.first.manifestVersion, 3);
    expect(progress.first.intraPageOffset, 0.4);
  });

  test(
    'clearUserData clears account data and retains device settings',
    () async {
      final now = DateTime(2026, 7, 22);
      final storageKey = List<String>.filled(64, 'a').join();
      await db
          .into(db.cachedFiles)
          .insert(
            CachedFilesCompanion.insert(
              id: 'file-1',
              fileName: 'private.txt',
              sizeBytes: 32,
              cachedAt: now,
            ),
          );
      await db
          .into(db.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              type: 'reader.progress',
              payload: '{"itemId":"book-1"}',
              createdAt: now,
            ),
          );
      await db
          .into(db.cachedReaderProgress)
          .insert(
            CachedReaderProgressCompanion.insert(
              itemId: 'book-1',
              updatedAt: now,
            ),
          );
      for (final userId in const ['user-1', 'user-2']) {
        await db
            .into(db.cachedReaderImages)
            .insert(
              CachedReaderImagesCompanion.insert(
                userId: userId,
                itemId: 'book-1',
                imagePath: 'cover.png',
                storageKey: storageKey,
                sizeBytes: 32,
                cachedAt: now,
                lastAccessedAt: now,
              ),
            );
        await db
            .into(db.syncClientStates)
            .insert(
              SyncClientStatesCompanion.insert(
                serverKey: 'https://example.test',
                userId: userId,
              ),
            );
      }
      await db
          .into(db.appBackdropSettingsTable)
          .insert(
            AppBackdropSettingsTableCompanion.insert(
              id: 'application',
              updatedAt: now,
            ),
          );

      await db.clearUserData('user-1');

      expect(await db.select(db.cachedFiles).get(), isEmpty);
      expect(await db.select(db.syncOperations).get(), isEmpty);
      expect(await db.select(db.cachedReaderProgress).get(), isEmpty);
      expect(
        (await db.select(db.cachedReaderImages).get()).map((row) => row.userId),
        ['user-2'],
      );
      expect(
        (await db.select(db.syncClientStates).get()).map((row) => row.userId),
        ['user-2'],
      );
      expect(await db.select(db.appBackdropSettingsTable).get(), hasLength(1));
    },
  );

  test(
    'schema v12 backdrop tables rename and purge retired local file assets',
    () async {
      await db.close();
      dbOpen = false;
      final rawDatabase = sqlite.sqlite3.openInMemory();
      rawDatabase.execute('''
      CREATE TABLE portal_local_backdrops (
        id TEXT NOT NULL PRIMARY KEY,
        path TEXT NOT NULL,
        title TEXT NOT NULL,
        media_type TEXT NOT NULL,
        source_type TEXT NOT NULL,
        source_directory TEXT,
        file_size INTEGER NOT NULL DEFAULT 0,
        modified_at INTEGER NOT NULL,
        width INTEGER,
        height INTEGER,
        duration_ms INTEGER,
        thumbnail_path TEXT,
        missing INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
      rawDatabase.execute('''
      CREATE TABLE portal_local_backdrop_settings (
        id TEXT NOT NULL PRIMARY KEY,
        enabled INTEGER NOT NULL DEFAULT 0,
        selected_backdrop_id TEXT,
        fit TEXT NOT NULL DEFAULT 'cover',
        dim_amount REAL NOT NULL DEFAULT 0.16,
        blur_amount REAL NOT NULL DEFAULT 0.0,
        video_muted INTEGER NOT NULL DEFAULT 1,
        updated_at INTEGER NOT NULL
      )
    ''');
      rawDatabase.execute('''
      INSERT INTO portal_local_backdrops (
        id, path, title, media_type, source_type, file_size,
        modified_at, missing, created_at, updated_at
      ) VALUES (
        'asset-1', 'D:/Media/scene.mp4', 'Scene', 'video', 'file', 2048,
        1783296000, 0, 1783296000, 1783296000
      )
    ''');
      rawDatabase.execute('''
      INSERT INTO portal_local_backdrop_settings (
        id, enabled, selected_backdrop_id, fit, dim_amount,
        blur_amount, video_muted, updated_at
      ) VALUES (
        'digital_gallery', 1, 'asset-1', 'cover', 0.08, 0.0, 1,
        1783296000
      )
    ''');
      rawDatabase.execute('PRAGMA user_version = 12');
      final migrated = LocalDatabase(NativeDatabase.opened(rawDatabase));
      addTearDown(migrated.close);

      final assets = await migrated.select(migrated.appBackdropAssets).get();
      final settings =
          await migrated.select(migrated.appBackdropSettingsTable).get();

      // v19 将背景事实来源改为服务端，本机 file/directory 素材行被清理。
      expect(assets, isEmpty);
      expect(settings, hasLength(1));
      expect(settings.single.id, 'application');
      expect(settings.single.selectedBackdropId, 'asset-1');
      expect(settings.single.separateDeviceBackdrops, isFalse);
      expect(settings.single.desktopBackdropId, isNull);
      expect(settings.single.mobileBackdropId, isNull);
    },
  );

  test(
    'schema v13 backdrop settings gain desktop and mobile selections',
    () async {
      await db.close();
      dbOpen = false;
      final rawDatabase = sqlite.sqlite3.openInMemory();
      rawDatabase.execute('''
      CREATE TABLE app_backdrop_settings (
        id TEXT NOT NULL PRIMARY KEY,
        enabled INTEGER NOT NULL DEFAULT 0,
        selected_backdrop_id TEXT,
        fit TEXT NOT NULL DEFAULT 'cover',
        dim_amount REAL NOT NULL DEFAULT 0.16,
        blur_amount REAL NOT NULL DEFAULT 0.0,
        video_muted INTEGER NOT NULL DEFAULT 1,
        updated_at INTEGER NOT NULL
      )
    ''');
      rawDatabase.execute('''
      INSERT INTO app_backdrop_settings (
        id, enabled, selected_backdrop_id, fit, dim_amount,
        blur_amount, video_muted, updated_at
      ) VALUES (
        'application', 1, 'asset-2', 'cover', 0.08, 0.0, 1,
        1783296000
      )
    ''');
      rawDatabase.execute('PRAGMA user_version = 13');
      final migrated = LocalDatabase(NativeDatabase.opened(rawDatabase));
      addTearDown(migrated.close);

      final settings =
          await migrated.select(migrated.appBackdropSettingsTable).get();

      expect(settings, hasLength(1));
      expect(settings.single.separateDeviceBackdrops, isFalse);
      expect(settings.single.desktopBackdropId, isNull);
      expect(settings.single.mobileBackdropId, isNull);
    },
  );

  test('schema v14 gains durable realtime synchronization tables', () async {
    await db.close();
    dbOpen = false;
    final rawDatabase = sqlite.sqlite3.openInMemory();
    rawDatabase.execute('PRAGMA user_version = 14');
    final migrated = LocalDatabase(NativeDatabase.opened(rawDatabase));
    addTearDown(migrated.close);

    await migrated
        .into(migrated.syncClientStates)
        .insert(
          SyncClientStatesCompanion.insert(
            serverKey: 'https://example.test',
            userId: 'user-1',
            cursor: const Value(42),
          ),
        );
    await migrated
        .into(migrated.syncPendingInvalidations)
        .insert(
          SyncPendingInvalidationsCompanion.insert(
            serverKey: 'https://example.test',
            userId: 'user-1',
            invalidationKey: 'files:file:file-1',
            scope: 'files',
            resourceType: 'file',
            revision: const Value(42),
            createdAt: DateTime(2026, 7, 17),
          ),
        );
    await migrated
        .into(migrated.syncProcessedEvents)
        .insert(
          SyncProcessedEventsCompanion.insert(
            serverKey: 'https://example.test',
            userId: 'user-1',
            eventId: 'event-1',
            sequenceNo: 42,
            processedAt: DateTime(2026, 7, 17),
          ),
        );

    expect(
      await migrated.select(migrated.syncClientStates).get(),
      hasLength(1),
    );
    expect(
      await migrated.select(migrated.syncPendingInvalidations).get(),
      hasLength(1),
    );
    expect(
      await migrated.select(migrated.syncProcessedEvents).get(),
      hasLength(1),
    );
  });

  test(
    'schema v15 purges unowned image blobs and creates file indexes',
    () async {
      await db.close();
      dbOpen = false;
      final rawDatabase = sqlite.sqlite3.openInMemory();
      rawDatabase.execute('''
      CREATE TABLE cached_reader_images (
        item_id TEXT NOT NULL,
        image_path TEXT NOT NULL,
        mime_type TEXT NOT NULL DEFAULT 'image/png',
        image_bytes BLOB NOT NULL,
        cached_at INTEGER NOT NULL,
        PRIMARY KEY (item_id, image_path)
      )
    ''');
      rawDatabase.execute('''
      INSERT INTO cached_reader_images (
        item_id, image_path, mime_type, image_bytes, cached_at
      ) VALUES ('book-1', 'images/cover.png', 'image/png', X'010203', 1)
    ''');
      rawDatabase.execute('PRAGMA user_version = 15');
      final migrated = LocalDatabase(NativeDatabase.opened(rawDatabase));
      addTearDown(migrated.close);
      final storageKey = List<String>.filled(64, 'a').join();

      expect(await migrated.select(migrated.cachedReaderImages).get(), isEmpty);

      await migrated
          .into(migrated.cachedReaderImages)
          .insert(
            CachedReaderImagesCompanion.insert(
              userId: 'user-1',
              itemId: 'book-1',
              imagePath: 'images/cover.png',
              storageKey: storageKey,
              sizeBytes: 3,
              cachedAt: DateTime(2026, 7, 18),
              lastAccessedAt: DateTime(2026, 7, 18),
            ),
          );

      final row =
          await migrated.select(migrated.cachedReaderImages).getSingle();
      expect(row.userId, 'user-1');
      expect(row.storageKey, storageKey);
      expect(row.sizeBytes, 3);
      expect(row.encryptionVersion, 2);
    },
  );

  test('schema v16 adds chapter ownership to cached annotations', () async {
    await db.close();
    dbOpen = false;
    final rawDatabase = sqlite.sqlite3.openInMemory();
    rawDatabase.execute('''
      CREATE TABLE cached_reader_annotations (
        id TEXT NOT NULL PRIMARY KEY,
        reader_item_id TEXT NOT NULL,
        start_offset INTEGER NOT NULL,
        end_offset INTEGER NOT NULL,
        highlight_text TEXT,
        note TEXT,
        color TEXT NOT NULL DEFAULT '#FFEB3B',
        created_at INTEGER NOT NULL
      )
    ''');
    rawDatabase.execute('''
      INSERT INTO cached_reader_annotations (
        id, reader_item_id, start_offset, end_offset, color, created_at
      ) VALUES ('annotation-1', 'book-1', 10, 20, '#FFEB3B', 1)
    ''');
    rawDatabase.execute('PRAGMA user_version = 16');
    final migrated = LocalDatabase(NativeDatabase.opened(rawDatabase));
    addTearDown(migrated.close);

    final legacy =
        await migrated.select(migrated.cachedReaderAnnotations).getSingle();
    expect(legacy.chapterId, isNull);

    await migrated
        .into(migrated.cachedReaderAnnotations)
        .insert(
          CachedReaderAnnotationsCompanion.insert(
            id: 'annotation-2',
            readerItemId: 'book-1',
            chapterId: const Value('chapter_2'),
            startOffset: 30,
            endOffset: 40,
            createdAt: DateTime(2026, 7, 31),
          ),
        );
    final current =
        await (migrated.select(migrated.cachedReaderAnnotations)
          ..where((table) => table.id.equals('annotation-2'))).getSingle();
    expect(current.chapterId, 'chapter_2');
  });
}
