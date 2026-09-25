import 'dart:convert';
import 'dart:typed_data';

import 'package:gbk_codec/gbk_codec.dart';
import 'package:omninest/core/config/file_size_thresholds.dart';

const int maxLocalSubtitleBytes = FileSizeThresholds.subtitleMaxBytes;

/// 解码本地字幕文件，兼容常见中文和 Unicode 编码。
String decodeSubtitleFile(Uint8List bytes) {
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

/// 根据字幕文件名推断 ISO 639 常用三字母语言代码。
String inferSubtitleLanguage(String fileName) {
  final normalized = fileName.toLowerCase();
  const languageMarkers = <String, List<String>>{
    'chi': ['.zh.', '.chi.', '.chs.', '.cht.', '_zh.', '-zh.'],
    'eng': ['.en.', '.eng.', '_en.', '-en.'],
    'jpn': ['.ja.', '.jpn.', '.jp.', '_ja.', '-ja.'],
    'kor': ['.ko.', '.kor.', '_ko.', '-ko.'],
    'fra': ['.fr.', '.fra.', '.fre.', '_fr.', '-fr.'],
    'deu': ['.de.', '.deu.', '.ger.', '_de.', '-de.'],
    'spa': ['.es.', '.spa.', '_es.', '-es.'],
  };
  for (final entry in languageMarkers.entries) {
    if (entry.value.any(normalized.contains)) {
      return entry.key;
    }
  }
  return 'und';
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
