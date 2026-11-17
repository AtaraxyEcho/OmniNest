import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

/// v27 的媒体进度表只有 media_id 主键；升级到 v28 时既要保留旧行，
/// 又要让同一设备上的不同账号各存一份。SQLite 不能原地改主键，
/// 只有拿一份真的 v27 文件打开才会走到搬迁语句。
void main() {
  test('旧媒体进度表升级后保留位置，并按账号隔离', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'media-progress-migration-',
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
      CREATE TABLE cached_media_progress (
        media_id TEXT NOT NULL,
        media_type TEXT NOT NULL,
        progress_percent REAL NOT NULL,
        position_seconds INTEGER NOT NULL,
        duration_seconds INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (media_id)
      )
    ''');
    legacy.execute('''
      INSERT INTO cached_media_progress (
        media_id, media_type, progress_percent, position_seconds,
        duration_seconds, updated_at
      ) VALUES ('shared:track-1', 'music', 0.5, 30, 60, 1780000000000)
    ''');
    legacy.userVersion = 27;
    legacy.close();

    final migrated = LocalDatabase(NativeDatabase(databaseFile));
    addTearDown(migrated.close);

    final legacyRows =
        await migrated.select(migrated.cachedMediaProgress).get();
    expect(legacyRows, hasLength(1), reason: '旧行没搬进新表，升级等于清空播放位置');
    expect(legacyRows.single.userId, '');
    expect(legacyRows.single.positionSeconds, 30);
    expect(legacyRows.single.progressPercent, 0.5);

    await migrated
        .into(migrated.cachedMediaProgress)
        .insert(
          CachedMediaProgressCompanion.insert(
            userId: const Value('user-b'),
            mediaId: 'shared:track-1',
            mediaType: 'music',
            progressPercent: 0.75,
            positionSeconds: 90,
            durationSeconds: 60,
            updatedAt: DateTime(2026, 10, 25),
          ),
        );

    final rows = await migrated.select(migrated.cachedMediaProgress).get();
    expect(
      rows.map((row) => row.userId),
      containsAll(<String>['', 'user-b']),
      reason: '同一 mediaId 必须能按账号并存',
    );
    expect(
      await _tableNames(migrated),
      isNot(contains('cached_media_progress_v27')),
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

Future<int> _userVersion(LocalDatabase database) async {
  final row = await database.customSelect('PRAGMA user_version').getSingle();
  return row.read<int>('user_version');
}
