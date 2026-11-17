import 'package:omninest/features/reader/data/epub_archive_source.dart';

/// 非原生平台不提供文件系统 EPUB 归档入口。
EpubArchiveSource openEpubArchiveFile(String path) {
  throw UnsupportedError('当前平台不支持文件型 EPUB 解析');
}
