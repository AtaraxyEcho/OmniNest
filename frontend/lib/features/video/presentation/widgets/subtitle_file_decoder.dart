import 'package:omninest/core/config/file_size_thresholds.dart';

const int maxLocalSubtitleBytes = FileSizeThresholds.subtitleMaxBytes;

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
