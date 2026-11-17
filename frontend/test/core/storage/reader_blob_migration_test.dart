import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  test('旧版本库升级时安全清除大体积旧图片 BLOB 并支持重开', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'reader-blob-migration-',
    );
    final databaseFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}legacy.sqlite',
    );
    addTearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    final legacyDatabase = sqlite.sqlite3.open(databaseFile.path);
    legacyDatabase.execute('''
      CREATE TABLE cached_reader_images (
        item_id TEXT NOT NULL,
        image_path TEXT NOT NULL,
        mime_type TEXT NOT NULL DEFAULT 'image/png',
        image_bytes BLOB NOT NULL,
        cached_at INTEGER NOT NULL,
        PRIMARY KEY (item_id, image_path)
      )
    ''');
    legacyDatabase.execute('''
      INSERT INTO cached_reader_images (
        item_id, image_path, mime_type, image_bytes, cached_at
      ) VALUES (
        'book-1', 'images/page-1.png', 'image/png', zeroblob(33554432), 1
      )
    ''');
    legacyDatabase.userVersion = 15;
    legacyDatabase.close();
    final legacyLength = await databaseFile.length();

    final migrated = LocalDatabase(NativeDatabase(databaseFile));
    await migrated.customSelect('SELECT 1').getSingle();
    final migratedColumns = await _columnNames(migrated);
    final currentSchemaVersion = migrated.schemaVersion;

    expect(currentSchemaVersion, greaterThan(15));
    expect(await migrated.select(migrated.cachedReaderImages).get(), isEmpty);
    expect(migratedColumns, isNot(contains('image_bytes')));
    expect(
      migratedColumns,
      containsAll(<String>[
        'user_id',
        'storage_key',
        'size_bytes',
        'encryption_version',
        'last_accessed_at',
      ]),
    );
    expect(await databaseFile.length(), lessThan(legacyLength + 1024 * 1024));
    await migrated.close();

    final reopened = LocalDatabase(NativeDatabase(databaseFile));
    addTearDown(reopened.close);
    await reopened.customSelect('SELECT 1').getSingle();

    expect(await _userVersion(reopened), currentSchemaVersion);
    expect(await _columnNames(reopened), isNot(contains('image_bytes')));
    expect(await reopened.select(reopened.cachedReaderImages).get(), isEmpty);
  });
}

Future<List<String>> _columnNames(LocalDatabase database) async {
  final rows =
      await database
          .customSelect("PRAGMA table_info('cached_reader_images')")
          .get();
  return rows.map((row) => row.read<String>('name')).toList(growable: false);
}

Future<int> _userVersion(LocalDatabase database) async {
  final row = await database.customSelect('PRAGMA user_version').getSingle();
  return row.read<int>('user_version');
}
