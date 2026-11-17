import 'package:archive/archive.dart';

/// EPUB 归档文件源。
abstract interface class EpubArchiveSource {
  /// 延迟解压的归档目录。
  Archive get archive;

  /// 归档压缩总字节数，用于解压比校验。
  ///
  /// 必须由源本身提供：逐条目取 `rawContent.length` 会把每个条目的压缩数据
  /// 整块复制进内存再丢弃，只为算一个总和。
  int get compressedBytes;

  /// 关闭归档底层文件句柄。
  void close();
}
