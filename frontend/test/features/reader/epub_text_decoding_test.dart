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

  test('UTF-16LE 带 BOM 的条目按双字节解码，不留 NUL 碎字', () {
    final bytes = _utf16Bytes(
      '<?xml version="1.0" encoding="UTF-16"?><html><body>第一章 中文</body></html>',
      bigEndian: false,
      withBom: true,
    );

    final decoded = decodeEpubText(bytes);

    expect(decoded, contains('第一章 中文'));
    expect(decoded, isNot(contains('\u0000')));
  });

  test('UTF-16BE 带 BOM 与无 BOM 都能识别', () {
    const text =
        '<?xml version="1.0" encoding="UTF-16"?><html><body>反向字节序</body></html>';

    expect(
      decodeEpubText(_utf16Bytes(text, bigEndian: true, withBom: true)),
      contains('反向字节序'),
    );
    // 无 BOM 时声明正则会被 NUL 打断，只能靠"< 落在奇字节"的字节形状判定。
    expect(
      decodeEpubText(_utf16Bytes(text, bigEndian: true, withBom: false)),
      contains('反向字节序'),
    );
  });

  test('UTF-16 代理对拼回 Supplementary 平面字符', () {
    final bytes = _utf16Bytes(
      '<?xml version="1.0" encoding="UTF-16"?><html><body>𠀋</body></html>',
      bigEndian: false,
      withBom: true,
    );

    expect(decodeEpubText(bytes), contains('𠀋'));
  });

  test('声明 Big5 的非 ASCII 条目显式失败，不再静默产出乱码', () {
    // 「中」的 Big5 字节 A4 67 不是合法 UTF-8 序列。
    final bytes = <int>[
      ...utf8.encode('<?xml version="1.0" encoding="Big5"?><html><body>'),
      0xA4,
      0x67,
      ...utf8.encode('</body></html>'),
    ];

    expect(
      () => decodeEpubText(bytes),
      throwsA(isA<EpubUnsupportedEncodingException>()),
    );
  });

  test('声明写错但内容是 ASCII 的条目仍可读', () {
    // 收紧静默解码不能把这类历史书籍一起判死：严格 UTF-8 能过就照读。
    final bytes = utf8.encode(
      '<?xml version="1.0" encoding="Windows-1252"?>'
      '<html><body>plain ascii</body></html>',
    );

    expect(decodeEpubText(bytes), contains('plain ascii'));
  });
}

/// 构造 UTF-16 字节序列的地面真值（不依赖被测解码器自己的编码路径）。
List<int> _utf16Bytes(
  String text, {
  required bool bigEndian,
  required bool withBom,
}) {
  final bytes = <int>[];
  if (withBom) {
    bytes.addAll(bigEndian ? [0xFE, 0xFF] : [0xFF, 0xFE]);
  }
  for (final unit in text.runes) {
    var code = unit;
    if (code > 0xFFFF) {
      code -= 0x10000;
      final high = 0xD800 + (code >> 10);
      final low = 0xDC00 + (code & 0x3FF);
      bytes.addAll(_utf16Units([high, low], bigEndian));
      continue;
    }
    bytes.addAll(_utf16Units([code], bigEndian));
  }
  return bytes;
}

List<int> _utf16Units(List<int> units, bool bigEndian) => [
  for (final unit in units)
    if (bigEndian) ...[unit >> 8, unit & 0xFF] else ...[unit & 0xFF, unit >> 8],
];
