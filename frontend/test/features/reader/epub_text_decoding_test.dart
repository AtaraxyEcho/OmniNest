import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/data/epub_parser_service.dart';

/// EPUB 内部文本解码回归测试（N-03）。
///
/// 修复前的测试用同一个坏编码器 `gbk.encode` 往返，会把缺陷一起证明为"通过"；
/// 这里改用 JDK `Charset.forName("GBK")` 生成的地面真值字节序列。
void main() {
  test('GBK 声明的 EPUB 条目按双字节解码而非逐字节 Latin-1', () {
    // 「第一章 中文内容测试」的 GBK 字节，10 字符 / 19 字节。
    final gbkBytes = <int>[
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
    final head = utf8.encode(
      '<?xml version="1.0" encoding="gbk"?>'
      '<html><body><p>',
    );
    final tail = utf8.encode('</p></body></html>');
    final bytes = <int>[...head, ...gbkBytes, ...tail];

    final decoded = decodeEpubText(bytes);

    expect(decoded, contains('第一章 中文内容测试'));
    expect(decoded, isNot(contains('µÚ')), reason: '出现 Latin-1 回退痕迹说明仍在逐字节解码');
  });

  test('UTF-8 条目正常解码且容忍坏字节', () {
    final xhtml =
        '<?xml version="1.0" encoding="utf-8"?><html><body>ok</body></html>';
    final bytes = <int>[...utf8.encode(xhtml), 0xFF];

    final decoded = decodeEpubText(bytes);

    expect(decoded, contains('<body>ok</body>'));
  });
}
