class ReaderAnnotation {
  const ReaderAnnotation({
    required this.id,
    required this.readerItemId,
    required this.startOffset,
    required this.endOffset,
    required this.color,
    required this.createdAt,
    this.chapterId,
    this.highlightText,
    this.note,
    this.version,
  });

  factory ReaderAnnotation.fromJson(Map<String, dynamic> json) {
    return ReaderAnnotation(
      id: json['id']?.toString() ?? '',
      readerItemId: json['readerItemId']?.toString() ?? '',
      startOffset: _asInt(json['startOffset']),
      endOffset: _asInt(json['endOffset']),
      chapterId: json['chapterId']?.toString(),
      highlightText: json['highlightText']?.toString(),
      note: json['note']?.toString(),
      color: json['color']?.toString() ?? '#FFEB3B',
      createdAt: _parseDateTime(json['createdAt']),
      version: _nullableInt(json['version']),
    );
  }

  final String id;
  final String readerItemId;
  final int startOffset;
  final int endOffset;

  /// 章节 ID（可选，用于按章节过滤批注）
  final String? chapterId;
  final String? highlightText;
  final String? note;
  final String color;
  final DateTime? createdAt;

  /// 服务端乐观锁版本；本地新建或旧缓存为 null，更新时不带前置条件。
  final int? version;
}

int _asInt(dynamic value) => switch (value) {
  int() => value,
  num() => value.toInt(),
  _ => int.tryParse(value?.toString() ?? '') ?? 0,
};

int? _nullableInt(dynamic value) {
  if (value == null || value.toString().isEmpty) return null;
  return _asInt(value);
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null || value.toString().isEmpty) return null;
  return DateTime.tryParse(value.toString().replaceFirst(' ', 'T'))?.toLocal();
}
