class ReaderBookmark {
  const ReaderBookmark({
    required this.id,
    required this.readerItemId,
    required this.charOffset,
    required this.progressPercent,
    required this.createdAt,
    this.chapterId,
    this.chapterTitle,
    this.note,
  });

  factory ReaderBookmark.fromJson(Map<String, dynamic> json) {
    return ReaderBookmark(
      id: json['id']?.toString() ?? '',
      readerItemId: json['readerItemId']?.toString() ?? '',
      charOffset: _asInt(json['charOffset']),
      progressPercent: _asDouble(json['progressPercent']),
      chapterId: json['chapterId']?.toString(),
      chapterTitle: json['chapterTitle']?.toString(),
      note: json['note']?.toString(),
      createdAt: _parseDateTime(json['createdAt']),
    );
  }

  final String id;
  final String readerItemId;
  final int charOffset;
  final double progressPercent;

  /// 书签所属章节标识；[charOffset] 是该章内的偏移，缺它无法定位回原章节。
  final String? chapterId;

  /// 章节标题（可选，用于书签列表展示）
  final String? chapterTitle;
  final String? note;
  final DateTime? createdAt;
}

/// 书签是否落在当前阅读位置所在的章节。
///
/// 章节归属缺失（无章目录的条目）时退回章内偏移比较。按整书判存会让全书
/// 只能存在一个书签，且取消时删掉的是别一章的那条。
bool bookmarkAtChapter(
  ReaderBookmark bookmark, {
  required String? chapterId,
  required int charOffset,
}) {
  final chapter = chapterId?.trim() ?? '';
  if (chapter.isEmpty) {
    return bookmark.charOffset == charOffset;
  }
  return bookmark.chapterId == chapter;
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

DateTime? _parseDateTime(dynamic value) {
  if (value == null || value.toString().isEmpty) return null;
  return DateTime.tryParse(value.toString().replaceFirst(' ', 'T'))?.toLocal();
}
