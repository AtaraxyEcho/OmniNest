import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/storage/local_database.dart';

/// 摘要：v31 的四条复合索引既要随新建库生成，也要在升级库上补出来。
///
/// 注解只影响 `createAll`（新库），已有安装走 `onUpgrade` 里的
/// `CREATE INDEX IF NOT EXISTS`；两处任缺一处，线上要么新库没索引，要么老库升级后
/// 仍全表扫描。
void main() {
  const indexNames = <String>[
    'idx_cached_reader_bookmarks_user_item',
    'idx_cached_reader_annotations_user_item',
    'idx_cached_reader_notes_user_item',
    'idx_sync_processed_events_server_user_time',
  ];

  Future<Set<String>> indexNamesOf(LocalDatabase database) async {
    final rows =
        await database
            .customSelect("select name from sqlite_master where type = 'index'")
            .get();
    return rows.map((row) => row.read<String>('name')).toSet();
  }

  test('新建库直接带上四条复合索引', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    // 触发建表：drift 在首次查询时才真正执行 createAll。
    await database.customSelect('select 1').get();

    expect(await indexNamesOf(database), containsAll(indexNames));
  });

  test('v30 升级到 v31 时补出四条索引', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'local-index-migration-',
    );
    final databaseFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}legacy.sqlite',
    );
    addTearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    // 先按当前 schema 建库，再把索引删掉并回退版本号：重开时走的就是
    // onUpgrade(30 -> 31) 这段迁移代码，而不是新建库分支。
    final created = LocalDatabase(NativeDatabase(databaseFile));
    await created.customSelect('select 1').get();
    for (final name in indexNames) {
      await created.customStatement('DROP INDEX IF EXISTS $name');
    }
    await created.customStatement('PRAGMA user_version = 30');
    await created.close();

    final upgraded = LocalDatabase(NativeDatabase(databaseFile));
    addTearDown(upgraded.close);
    await upgraded.customSelect('select 1').get();

    expect(await indexNamesOf(upgraded), containsAll(indexNames));
  });
}
