import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbk_codec/gbk_codec.dart';
import 'package:omninest/core/utils/text_file_decoder.dart';

/// 本地文本文件（字幕、歌词、TXT）的编码容错解码。
void main() {
  test('解码 UTF-8 BOM 文件', () {
    final bytes = Uint8List.fromList([
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode('字幕内容'),
    ]);

    expect(decodeTextFileBytes(bytes), '字幕内容');
  });

  test('解码无 BOM 的 UTF-8 文件', () {
    expect(
      decodeTextFileBytes(Uint8List.fromList(utf8.encode('[00:12.30]歌词第一行'))),
      contains('歌词第一行'),
    );
  });

  test('解码 GBK 文件', () {
    final bytes = Uint8List.fromList(gbk_bytes.encode('中文字幕'));

    expect(decodeTextFileBytes(bytes), '中文字幕');
  });

  test('GBK 中文歌词不再抛异常', () {
    // 严格 utf8 解码在这类字节上抛 FormatException，正是选择歌词文件失败的成因。
    final bytes = Uint8List.fromList(gbk_bytes.encode('[02:02.15]夜空中最亮的星'));

    expect(() => utf8.decode(bytes), throwsFormatException);
    expect(decodeTextFileBytes(bytes), '[02:02.15]夜空中最亮的星');
  });

  test('解码 UTF-16 文件并剥掉 BOM', () {
    const text = '第一行\n第二行';
    final littleEndian = Uint8List.fromList([
      0xFF,
      0xFE,
      ..._utf16Bytes(text, littleEndian: true),
    ]);
    final bigEndian = Uint8List.fromList([
      0xFE,
      0xFF,
      ..._utf16Bytes(text, littleEndian: false),
    ]);

    expect(decodeTextFileBytes(littleEndian), text);
    expect(decodeTextFileBytes(bigEndian), text);
  });

  test('空文件解码为空字符串', () {
    expect(decodeTextFileBytes(Uint8List(0)), isEmpty);
  });
}

List<int> _utf16Bytes(String text, {required bool littleEndian}) {
  final bytes = <int>[];
  for (final unit in text.codeUnits) {
    final low = unit & 0xFF;
    final high = (unit >> 8) & 0xFF;
    bytes.addAll(littleEndian ? [low, high] : [high, low]);
  }
  return bytes;
}
