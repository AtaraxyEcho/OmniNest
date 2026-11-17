import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbk_codec/gbk_codec.dart';
import 'package:omninest/features/reader/data/txt_parser_service.dart';

/// TXT 解码与分段链回归测试。
///
/// 覆盖缺陷：D-04（GBK 解码实为逐字节 Latin-1）、D-11（只按空行分段）、
/// N-04（BOM 后坏字节直接抛出）、N-05/D-07（两端偏移域必须一致）。
///
/// GBK 字节序列由 JDK `Charset.forName("GBK")` 生成为地面真值：
/// 「中文」= D6 D0 CE C4；「第一章 中文内容测试」= B5 DA D2 BB D5 C2 20 D6 D0 CE C4
/// C4 DA C8 DD B2 E2 CA D4；「　　第一回 灵根育孕」= A1 A1 A1 A1 B5 DA D2 BB BB D8 20
/// C1 E9 B8 F9 D3 FD D4 D0；全角空格 U+3000 = A1 A1。
void main() {
  const gbkChinese = <int>[0xD6, 0xD0, 0xCE, 0xC4];
  const gbkTitle = <int>[
    0xB5,
    0xDA,
    0xD2,
    0xBB,
    0xD5,
    0xC2,
    0x20,
    0xD6,
    0xD0,
    0xCE,
    0xC4,
    0xC4,
    0xDA,
    0xC8,
    0xDD,
    0xB2,
    0xE2,
    0xCA,
    0xD4,
  ];
  const gbkIndentedHeading = <int>[
    0xA1,
    0xA1,
    0xA1,
    0xA1,
    0xB5,
    0xDA,
    0xD2,
    0xBB,
    0xBB,
    0xD8,
    0x20,
    0xC1,
    0xE9,
    0xB8,
    0xF9,
    0xD3,
    0xFD,
    0xD4,
    0xD0,
  ];

  final parser = TxtParserService();
  Uint8List bytesOf(List<int> values) => Uint8List.fromList(values);
  int paragraphCount(String xhtml) => '<p>'.allMatches(xhtml).length;

  group('GBK 解码正确性', () {
    test('双字节 GBK 解码为汉字而不是两个 Latin-1 字符', () {
      final decoded = parser.decodeText(bytesOf(gbkChinese));

      expect(decoded, '中文');
      expect(decoded.length, 2);
    });

    test('GBK 标题行解码后字符数与 Java 解码一致', () {
      final decoded = parser.decodeText(bytesOf(gbkTitle));

      expect(decoded, '第一章 中文内容测试');
      expect(decoded.length, 10);
    });

    test('GBK 全角空格缩进解码为 U+3000', () {
      final decoded = parser.decodeText(bytesOf(gbkIndentedHeading));

      expect(decoded, '　　第一回 灵根育孕');
      expect(decoded.codeUnitAt(0), 0x3000);
    });

    test('混合 ASCII 与 GBK 双字节时按双字节计数', () {
      final decoded = parser.decodeText(bytesOf([0x41, 0x42, 0xC8, 0xDD]));

      expect(decoded.startsWith('AB'), isTrue);
      expect(decoded.length, 3);
    });

    test('包内 gbk 变体对字节流等价 Latin-1，禁止回退使用', () {
      // 该断言记录缺陷根因：gbk 的映射表以双字节码元为键，逐字节查表永不命中。
      // 若有人把解码链改回 gbk，本用例与上面的汉字断言会一起失败。
      expect(gbk.decode(gbkChinese), isNot('中文'));
      expect(gbk_bytes.decode(gbkChinese), '中文');
    });
  });

  group('偏移域一致性', () {
    test('CRLF 与 CR 一律规范化为单个 LF', () {
      final decoded = parser.decodeText(
        bytesOf(utf8.encode('第一章 甲\r\n正文\r第二章 乙\n正文')),
      );

      expect(decoded, '第一章 甲\n正文\n第二章 乙\n正文');
      expect(decoded.length, 17);
    });

    test('UTF-8 BOM 不进入解码结果', () {
      final decoded = parser.decodeText(
        bytesOf([0xEF, 0xBB, 0xBF, ...utf8.encode('第一章 甲\n正文')]),
      );

      expect(decoded, '第一章 甲\n正文');
    });

    test('BOM 后跟坏字节不得抛出，必须替换后继续', () {
      final decoded = parser.decodeText(
        bytesOf([0xEF, 0xBB, 0xBF, 0xFF, ...utf8.encode('正文')]),
      );

      expect(decoded.contains('\uFFFD'), isTrue);
      expect(decoded.contains('正文'), isTrue);
    });
  });

  group('分段模式判定', () {
    test('Mode P：段间无空行且段首全角缩进时逐行成段', () {
      const text = '　　第一行正文内容。\n　　第二行正文内容。\n　　第三行正文内容。\n';

      final xhtml = parser.textToXhtml(text);

      expect(paragraphCount(xhtml), 3);
      expect(xhtml, contains('　　第一行正文内容。'));
    });

    test('Mode W：无缩进的硬换行不制造假段落', () {
      const line = '这是被固定宽度断开的正文，行首没有缩进。';
      final text = List.generate(12, (_) => line).join('\n');

      final xhtml = parser.textToXhtml(text);

      expect(paragraphCount(xhtml), 1);
      expect(xhtml, contains('$line\n$line'));
    });

    test('Mode W：空行分段保持原有行为', () {
      const text = '第一段内容。\n\n第二段内容。\n\n第三段内容。\n';

      final xhtml = parser.textToXhtml(text);

      expect(paragraphCount(xhtml), 3);
    });

    test('GBK 中文书解码后按行成段且偏移域可复用', () {
      final decoded = parser.decodeText(
        bytesOf([...gbkIndentedHeading, 0x0A, ...gbkTitle, 0x0A]),
      );

      // 19+1+19+1 字节 → 10+1+10+1 字符，与服务端按解码字符累计的偏移一致。
      expect(decoded.length, 22);
      final xhtml = parser.textToXhtml(decoded);
      expect(paragraphCount(xhtml), 2);
      expect(xhtml, contains('第一回 灵根育孕'));
      expect(xhtml, contains('第一章 中文内容测试'));
    });

    test('按偏移切片只取本章内容', () {
      const text = '第一章 甲\n本章正文。\n第二章 乙\n本章正文二。';

      final xhtml = parser.textToXhtml(parser.rawChapterSlice(text, 0, 11));

      expect(xhtml, contains('本章正文。'));
      expect(xhtml, isNot(contains('第二章')));
    });
  });

  group('偏移对齐哨兵', () {
    test('切片首行与本章标题一致时判定为对齐', () {
      expect(
        TxtParserService.sliceStartsWithTitle(
          '第一章 甲\n本章正文。',
          '第一章 甲',
          chapterOrdinal: 1,
        ),
        isTrue,
      );
    });

    test('全角缩进在标题或切片任一侧都不影响判定', () {
      expect(
        TxtParserService.sliceStartsWithTitle(
          '　　第一章 甲\n正文',
          '　　第一章 甲',
          chapterOrdinal: 1,
        ),
        isTrue,
      );
      expect(
        TxtParserService.sliceStartsWithTitle(
          '　　第一章 甲\n正文',
          '第一章 甲',
          chapterOrdinal: 1,
        ),
        isTrue,
      );
    });

    test('标题被入库截断时仍判定为对齐', () {
      expect(
        TxtParserService.sliceStartsWithTitle(
          '第一章 很长的标题内容\n正文',
          '第一章',
          chapterOrdinal: 1,
        ),
        isTrue,
      );
    });

    test('入库标题已归一掉重复序号时仍判定为对齐', () {
      // 抓取站在原标题前又补了一个号，入库的是归一后的显示标题；
      // 哨兵必须对首行施加同一归一再比，否则整本书会被判成偏移漂移。
      expect(
        TxtParserService.sliceStartsWithTitle(
          '第1章 第1章 天胡开局\n永和五年，时值七月。',
          '第1章 天胡开局',
          chapterOrdinal: 1,
        ),
        isTrue,
      );
      expect(
        TxtParserService.sliceStartsWithTitle(
          '第38章 第1章 吴兴\n正文',
          '第38章 吴兴',
          chapterOrdinal: 38,
        ),
        isTrue,
      );
    });

    test('归一后仍然错章时判定为不对齐', () {
      expect(
        TxtParserService.sliceStartsWithTitle(
          '第2章 第2章 织屩之徒\n正文',
          '第1章 天胡开局',
          chapterOrdinal: 1,
        ),
        isFalse,
      );
    });

    test('偏移错位到别章时判定为不对齐', () {
      expect(
        TxtParserService.sliceStartsWithTitle(
          '第二章 乙\n正文',
          '第一章 甲',
          chapterOrdinal: 1,
        ),
        isFalse,
      );
    });

    test('后端未识别章节时的单章"正文"不参与判定', () {
      expect(
        TxtParserService.sliceStartsWithTitle(
          '任意正文起始行',
          '正文',
          chapterOrdinal: 1,
        ),
        isTrue,
      );
    });

    test('空切片判定为不对齐', () {
      expect(
        TxtParserService.sliceStartsWithTitle('', '第一章 甲', chapterOrdinal: 1),
        isFalse,
      );
    });
  });
}
