class ReaderProgress {
  const ReaderProgress({
    required this.readerItemId,
    required this.charOffset,
    required this.progressPercent,
    required this.readingMode,
    required this.updatedAt,
    this.chapterId,
    this.pageId,
    this.pageIndex,
    this.pageFingerprint,
    this.sourceId,
    this.sourcePageIndex,
    this.catalogKey,
    this.manifestVersion,
    this.intraPageOffset,
  });

  factory ReaderProgress.fromJson(Map<String, dynamic> json) {
    return ReaderProgress(
      readerItemId: json['readerItemId']?.toString() ?? '',
      charOffset: _asInt(json['charOffset']),
      progressPercent: _asDouble(json['progressPercent']),
      readingMode: json['readingMode']?.toString() ?? 'scroll',
      chapterId: json['chapterId']?.toString(),
      updatedAt: _parseDateTime(json['updatedAt']),
      pageId: json['pageId']?.toString(),
      pageIndex: json['pageIndex'] as int?,
      pageFingerprint: json['pageFingerprint']?.toString(),
      sourceId: json['sourceId']?.toString(),
      sourcePageIndex: json['sourcePageIndex'] as int?,
      catalogKey: json['catalogKey']?.toString(),
      manifestVersion: json['manifestVersion'] as int?,
      intraPageOffset: _asDoubleNullable(json['intraPageOffset']),
    );
  }

  final String readerItemId;

  /// 章节内字符偏移，与 chapterId 共同构成精确位置。
  final int charOffset;

  /// 全书进度比例（0-1），仅用于 UI 显示，不参与位置恢复。
  final double progressPercent;
  final String readingMode;
  final String? chapterId;
  final DateTime? updatedAt;

  /// 漫画页面 ID（用于精确定位）
  final String? pageId;

  /// 漫画页面索引
  final int? pageIndex;

  /// 漫画页面指纹（防篡改校验）
  final String? pageFingerprint;

  /// 漫画来源文件 ID
  final String? sourceId;

  /// 漫画页面在来源文件内的索引
  final int? sourcePageIndex;

  /// 漫画目录键
  final String? catalogKey;

  /// 漫画清单版本号
  final int? manifestVersion;

  /// 漫画：页内偏移（滚动模式，0.0-1.0）
  final double? intraPageOffset;

  /// 阅读模式别名
  String get mode => readingMode;
}

int _asInt(dynamic value) => switch (value) {
  int() => value,
  num() => value.toInt(),
  _ => int.tryParse(value?.toString() ?? '') ?? 0,
};

double _asDouble(dynamic value) => switch (value) {
  double() => value,
  num() => value.toDouble(),
  _ => double.tryParse(value?.toString() ?? '') ?? 0.0,
};

double? _asDoubleNullable(dynamic value) {
  if (value == null) return null;
  return switch (value) {
    double() => value,
    num() => value.toDouble(),
    _ => double.tryParse(value.toString()),
  };
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null || value.toString().isEmpty) return null;
  return DateTime.tryParse(value.toString().replaceFirst(' ', 'T'))?.toLocal();
}
