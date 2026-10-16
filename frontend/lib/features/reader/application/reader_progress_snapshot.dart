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
      chapterProgress: _asDouble(payload['chapterProgress']),
      // 本地行带全书比例：停在非首章章首时，它是这条快照唯一的"我读过这里"证据。
      bookProgress:
          payload['bookProgress'] == null
              ? null
              : _asDouble(payload['bookProgress']),
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

  /// 是否携带显式阅读位置。
  ///
  /// 除偏移与比例之外，带章节归属且有记录时刻的快照也算可读位置：用户主动
  /// 跳到第 10 章章首后退出，三个数值字段都是 0，若不认这条快照，服务端停在
  /// 第 2 章的旧位置就会在 `latest()` 的"另一侧不可读"分支里无条件胜出，
  /// 无视时间戳把进度回退。零时间戳的初始化占位仍靠 [updatedAt] 为空排除。
  bool get hasReadableProgress =>
      chapterId.isNotEmpty &&
      (charOffset > 0 ||
          chapterProgress > 0 ||
          (bookProgress ?? 0) > 0 ||
          updatedAt != null);

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
  /// 两侧都带章节归属与记录时刻时一律按时刻比较；只有没有任何位置证据
  /// （偏移、章内比例、全书比例、记录时刻全空）的一方才被排除，避免开书时
  /// 写入的无时间戳 chapter_0(0,0) 占位把用户从正文章拉回封面。
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
