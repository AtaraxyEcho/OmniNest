import 'dart:convert';
import 'dart:typed_data';

import 'package:gbk_codec/gbk_codec.dart';

/// 解码本地文本文件字节，兼容常见中文与 Unicode 编码。
///
/// 判定次序与 `TxtParserService._decodeText`、后端 `ReaderTextParser.detectCharset` 保持一致：
/// BOM/UTF-16 → 严格 UTF-8 → GBK → Latin-1。字幕、歌词（LRC/SRT/VTT）与纯文本都走这一份，
/// 避免同一条规则在各 feature 各写一遍后漂回。
///
/// `gbk` 的映射表以双字节 GBK 码元为键，逐字节查表永不命中（等价 Latin-1），
/// 必须使用同包内按双字节组合查表的 `gbk_bytes`。
String decodeTextFileBytes(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3));
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: false);
  }
  try {
    return utf8.decode(bytes, allowMalformed: false);
  } on FormatException {
    try {
      return gbk_bytes.decode(bytes);
    } on Object {
      return latin1.decode(bytes);
    }
  }
}

String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
  final codeUnits = <int>[];
  for (var index = 0; index + 1 < bytes.length; index += 2) {
    final first = bytes[index];
    final second = bytes[index + 1];
    codeUnits.add(littleEndian ? first | (second << 8) : (first << 8) | second);
  }
  return String.fromCharCodes(codeUnits);
}
