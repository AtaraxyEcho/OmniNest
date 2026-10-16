import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/domain/chapter_title_normalizer.dart';

/// 章名序号归一的判据表。
///
/// 这张表与后端 `ReaderTextParserTest.normalizesRepeatedChapterNumberTokens`
/// 逐条同值：入库标题由后端归一，客户端要对切片首行施加**同一**归一才能比对
/// （见 `TxtParserService.sliceStartsWithTitle`），两份实现算出不同结果就会把
/// 整本书判成偏移漂移。改判据时两侧都要改。
void main() {
  /// {标题原文, 本章目录位次, 归一结果}
  const cases = <List<Object>>[
    ['第1章 第1章 天胡开局', 1, '第1章 天胡开局'],
    ['第10章 第10章 屯将（下）', 10, '第10章 屯将（下）'],
    ['第38章 第1章 吴兴', 38, '第38章 吴兴'],
    ['第38章 第1章 吴兴', 42, '第38章 吴兴'],
    ['第38章 第1章 吴兴', 1, '第1章 吴兴'],
    ['Chapter 3 Chapter 3 The Dawn', 3, 'Chapter 3 The Dawn'],
    ['第二十三章 第二十三章 甲', 23, '第二十三章 甲'],
    ['第23章 第二十三章 甲', 23, '第23章 甲'],
    ['第一百二十章 甲', 120, '第一百二十章 甲'],
    ['第一千二百三十四章 甲', 1234, '第一千二百三十四章 甲'],
    ['第一〇八章 甲', 108, '第一〇八章 甲'],
    ['第一百一章 甲', 110, '第一百一章 甲'],
    ['第一百零一章 甲', 101, '第一百零一章 甲'],
    ['第二五六章 甲', 256, '第二五六章 甲'],
    ['第2章 2、小标题', 2, '第2章 小标题'],
    ['第1章： 第1章： 天胡开局', 1, '第1章 天胡开局'],
    ['第一章 甲', 1, '第一章 甲'],
    ['第1章 天胡开局', 1, '第1章 天胡开局'],
    ['1、《覆汉》实体书', 2, '1、《覆汉》实体书'],
    ['上架感言', 48, '上架感言'],
    ['第一卷完。113', 41, '第一卷完。113'],
    ['　　第一章 第一章 甲', 1, '　　第一章 第一章 甲'],
    ['', 1, ''],
  ];

  for (final entry in cases) {
    final raw = entry[0] as String;
    final ordinal = entry[1] as int;
    final expected = entry[2] as String;

    test('位次 $ordinal｜$raw → $expected', () {
      expect(normalizeChapterTitle(raw, ordinal), expected);
    });
  }

  test('归一是幂等的：对已归一的标题再算一次不变', () {
    for (final entry in cases) {
      final normalized = entry[2] as String;
      expect(
        normalizeChapterTitle(normalized, entry[1] as int),
        normalized,
        reason: '入库标题会被哨兵二次施加归一，不幂等就会比对不上',
      );
    }
  });

  test('标题正文不参与序号比对，只剥前导标记', () {
    expect(normalizeChapterTitle('第5章 复盘第4章的伏笔', 5), '第5章 复盘第4章的伏笔');
  });

  /// 与后端 `ReaderTextParserTest.normalizesTitlesAgainstTitledChapterOrdinalWhenPreambleExists`
  /// 同口径：客户端比对切片首行时用的位次必须与后端建清单时一致，否则整本书被判成偏移漂移。
  test('前置「正文」导言不占标题位次', () {
    expect(
      titledChapterOrdinal(['正文', '第1章 甲', '第2章 乙'], 2),
      2,
      reason: '清单顺位是 3，但只有带标题的章计数',
    );
    expect(titledChapterOrdinal(['第1章 甲', '第2章 乙'], 1), 2);
    expect(titledChapterOrdinal(['第1章 甲', '第2章 乙', '正文'], 2), 3);
    expect(titledChapterOrdinal(const <String>[], 1), 2, reason: '清单取不到时退回顺位');
  });
}
