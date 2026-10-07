/// 前端文件大小阈值统一定义，与后端 `MediaProcessingLimitsProperties` 对齐。
///
/// 业务代码只读本配置，不再散落魔法数。默认值与历史硬编码一致，避免隐性收紧。
abstract final class FileSizeThresholds {
  /// 头像上传上限（5 MiB）。
  static const int avatarUploadMaxBytes = 5 * 1024 * 1024;

  /// 文本预览 Range 读取上限（1 MiB）。
  static const int textPreviewMaxBytes = 1024 * 1024;

  /// 阅读封面读取上限（12 MiB，与后端 maxReaderCoverBytes 对齐取前端历史值）。
  static const int readerCoverMaxBytes = 12 * 1024 * 1024;

  /// Web 端电子书下载上限（32 MiB）。
  static const int webBookMaxBytes = 32 * 1024 * 1024;

  /// Web 端 PDF 下载上限（128 MiB）。
  static const int webPdfMaxBytes = 128 * 1024 * 1024;

  /// 字幕内容上限（2 MiB，前端本地解码限制）。
  static const int subtitleMaxBytes = 2 * 1024 * 1024;

  /// EPUB 封面提取上限（12 MiB）。
  static const int epubCoverMaxBytes = 12 * 1024 * 1024;

  /// Reader 本地缓存目录上限（500 MiB）。
  static const int readerLocalCacheMaxBytes = 500 * 1024 * 1024;

  /// Web 与 TXT 整包解析内存上限（32 MiB）。
  static const int readerInMemoryParseMaxBytes = 32 * 1024 * 1024;

  /// 原生平台整包解析内存上限（64 MiB）。
  static const int readerNativeParseMaxBytes = 64 * 1024 * 1024;

  /// 阅读章节图片总量上限（64 MiB）。
  static const int readerChapterImageMaxBytes = 64 * 1024 * 1024;

  /// 阅读章节内联单图上限（20 MiB）。
  static const int readerInlineImageMaxBytes = 20 * 1024 * 1024;

  /// 阅读单张图片读取上限（64 MiB）。
  static const int readerImageMaxBytes = 64 * 1024 * 1024;

  /// 阅读图片缓存上限（32 MiB，内容图与漫画加载器共用）。
  static const int readerImageCacheMaxBytes = 32 * 1024 * 1024;

  /// EPUB 解压总量上限（1 GiB，压缩炸弹防护）。
  static const int epubMaxExpandedBytes = 1024 * 1024 * 1024;

  /// EPUB 文本条目上限（8 MiB）。
  static const int epubMaxTextEntryBytes = 8 * 1024 * 1024;

  /// EPUB 归档实例内保留的已解压条目字节上限（32 MiB）。
  ///
  /// 条目解压后不能就地清空：archive 4.x 的 `ArchiveFile.clear()` 会连同内容来源一起丢弃，
  /// 之后再读同一条目只会得到 0 字节。因此解压结果随归档实例保留，累计到本上限时
  /// 释放整个归档（含文件句柄），下次使用时重新解压目录。
  static const int epubRetainedEntryBytes = 32 * 1024 * 1024;

  /// EPUB 解压比率检查启用阈值（64 MiB）。
  static const int epubRatioCheckThresholdBytes = 64 * 1024 * 1024;

  /// TXT 解码转入 isolate 的阈值（2 MiB）。
  static const int txtDecodeIsolateThresholdBytes = 2 * 1024 * 1024;
}
