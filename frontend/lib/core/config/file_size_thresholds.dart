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
}
