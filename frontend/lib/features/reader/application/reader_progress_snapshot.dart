import 'package:omninest/features/reader/domain/reader_models.dart';

/// 阅读进度快照
///
/// 统一本地进度、服务端进度、路由传递进度的数据格式，
/// 用于在阅读器视图中恢复和保存阅读位置。
///
/// ## 字段语义
///
/// - [charOffset] — 章节内字符偏移，用于精确定位恢复（跨端通用）
/// - [chapterProgress] — 章节内滚动比例（0-1），用于本地快速恢复
/// - [bookProgress] — 全书进度（0-1），null 表示口径无法确定；
///   章内比例不得填入此字段，否则任意长章章尾会被记成接近读完
/// - [chapterId] — 章节 ID
class ReaderProgressSnapshot {
  ReaderProgressSnapshot({
    required this.chapterId,
    this.charOffset = 0,
    this.bookProgress,
    this.chapterProgress = 0.0,
    this.chapterTitle = '',
    this.mode = 'scroll',
    this.manifestVersion,
    this.updatedAt,
  });

  /// 从本地 SQLite 存储的 Map 构造
  factory ReaderProgressSnapshot.fromLocal(Map<String, dynamic>? payload) {
    if (payload == null) return ReaderProgressSnapshot(chapterId: '');
    return ReaderProgressSnapshot(
      chapterId: payload['chapterId']?.toString() ?? '',
      charOffset: _asInt(payload['charOffset']),
      // 本地行只存章内口径，全书进度需要清单才能算出。
      chapterProgress: _asDouble(payload['chapterProgress']),
      chapterTitle: payload['chapterTitle']?.toString() ?? '',
      mode: payload['mode']?.toString() ?? 'scroll',
      manifestVersion:
          payload['manifestVersion'] == null
              ? null
              : _asInt(payload['manifestVersion']),
      updatedAt: _parseDateTime(payload['updatedAt']),
    );
  }

  /// 从服务端 [ReaderProgress] 构造
  ///
  /// 服务端返回的 progressPercent 是全书进度（仅用于显示），
  /// 恢复定位使用 chapterId + charOffset。
  factory ReaderProgressSnapshot.fromServer(ReaderProgress? progress) {
    if (progress == null) return ReaderProgressSnapshot(chapterId: '');
    // 兼容 0-100 和 0-1 两种格式
    final raw = progress.progressPercent;
    final normalized =
        raw > 1 ? (raw / 100).clamp(0.0, 1.0) : raw.clamp(0.0, 1.0);
    return ReaderProgressSnapshot(
      chapterId: progress.chapterId ?? '',
      charOffset: progress.charOffset,
      bookProgress: normalized, // 全书进度，仅显示用
      mode: progress.readingMode,
      manifestVersion: progress.manifestVersion,
      updatedAt: progress.updatedAt,
    );
  }

  final String chapterId;

  /// 章节内字符偏移，用于精确定位恢复（跨端通用）。
  final int charOffset;

  /// 全书进度（0-1）；null 表示清单或本章字符数尚不可用。
  final double? bookProgress;

  /// 章节内滚动比例（0-1），用于本地快速恢复。
  final double chapterProgress;

  final String chapterTitle;
  final String mode;

  /// 写入时的章节清单版本；null 表示未知（历史行或服务端未下发）。
  ///
  /// 服务端重解析会改变章节边界与字符偏移口径，版本不一致时字符偏移
  /// 不再可比，只能按章首恢复。
  final int? manifestVersion;
  final DateTime? updatedAt;

  /// 是否有可恢复的阅读进度
  bool get hasReadableProgress =>
      chapterId.isNotEmpty &&
      (charOffset > 0 || chapterProgress > 0 || (bookProgress ?? 0) > 0);

  /// 降级为章首恢复：清单版本变化后字符偏移不再可比。
  ReaderProgressSnapshot degradeToChapterStart() {
    return ReaderProgressSnapshot(
      chapterId: chapterId,
      chapterTitle: chapterTitle,
      mode: mode,
      manifestVersion: manifestVersion,
      updatedAt: updatedAt,
    );
  }

  /// 从两个快照中选取更新时间较新的一方。
  ///
  /// 零进度快照（无 charOffset 且无 progress）不得作为“最新”，
  /// 否则开书时写入的 chapter_0(0,0) 会把用户从正文章拉回封面。
  static ReaderProgressSnapshot? latest(
    ReaderProgressSnapshot? a,
    ReaderProgressSnapshot? b,
  ) {
    final readableA = a?.hasReadableProgress ?? false;
    final readableB = b?.hasReadableProgress ?? false;
    if (readableA && !readableB) {
      return a;
    }
    if (readableB && !readableA) {
      return b;
    }
    if (a == null) return b;
    if (b == null) return a;
    final aTime = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return aTime.isAfter(bTime) ? a : b;
  }

  /// 从章节列表中根据进度快照解析目标章节
  ///
  /// 如果快照中有 chapterId 且在列表中找到匹配项，则返回该项；
  /// 否则返回列表第一章。
  static ReaderChapter? resolveChapter(
    List<ReaderChapter> chapters,
    ReaderProgressSnapshot? snapshot,
  ) {
    if (chapters.isEmpty) return null;
    if (snapshot != null && snapshot.chapterId.isNotEmpty) {
      final match = chapters.where((c) => c.id == snapshot.chapterId);
      if (match.isNotEmpty) return match.first;
    }
    return chapters.first;
  }
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
