/// 阅读器导入状态常量。
///
/// 与后端 ReaderItem.importStatus 和 ReaderSourceStatus 对应。
abstract final class ReaderImportStatus {
  static const String pending = 'PENDING';
  static const String parsing = 'PARSING';
  static const String ready = 'READY';
  static const String partialFailed = 'PARTIAL_FAILED';
  static const String failed = 'FAILED';
}

/// 漫画来源解析状态常量。
///
/// 与后端 ReaderSourceStatus 枚举对应。
abstract final class ReaderSourceStatus {
  static const String pending = 'PENDING';
  static const String parsing = 'PARSING';
  static const String ready = 'READY';
  static const String failed = 'FAILED';
}
