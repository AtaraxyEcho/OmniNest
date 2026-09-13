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
/// - [progress] — 全书进度（0-1），仅用于 UI 显示
/// - [chapterId] — 章节 ID
class ReaderProgressSnapshot {
  ReaderProgressSnapshot({
    required this.chapterId,
    this.charOffset = 0,
    this.progress = 0.0,
    this.chapterProgress = 0.0,
    this.chapterTitle = '',
    this.mode = 'scroll',
    this.updatedAt,
  });

  /// 从本地 SQLite 存储的 Map 构造
  factory ReaderProgressSnapshot.fromLocal(Map<String, dynamic>? payload) {
    if (payload == null) return ReaderProgressSnapshot(chapterId: '');
    return ReaderProgressSnapshot(
      chapterId: payload['chapterId']?.toString() ?? '',
      charOffset: _asInt(payload['charOffset']),
      progress: _asDouble(payload['chapterProgress']),
      chapterProgress: _asDouble(payload['chapterProgress']),
      chapterTitle: payload['chapterTitle']?.toString() ?? '',
      mode: payload['mode']?.toString() ?? 'scroll',
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
      progress: normalized, // 全书进度，仅显示用
      mode: progress.readingMode,
      updatedAt: progress.updatedAt,
    );
  }

  /// 从路由传递的 payload 构造
  factory ReaderProgressSnapshot.fromPayload(Map<String, dynamic>? payload) {
    if (payload == null) return ReaderProgressSnapshot(chapterId: '');
    return ReaderProgressSnapshot(
      chapterId: payload['chapterId']?.toString() ?? '',
      charOffset: _asInt(payload['charOffset']),
      progress: _asDouble(payload['progress']),
      chapterProgress: _asDouble(payload['chapterProgress']),
      chapterTitle: payload['chapterTitle']?.toString() ?? '',
      mode: payload['mode']?.toString() ?? 'scroll',
      updatedAt: _parseDateTime(payload['updatedAt']),
    );
  }

  final String chapterId;

  /// 章节内字符偏移，用于精确定位恢复（跨端通用）。
  final int charOffset;

  /// 全书进度（0-1），仅用于 UI 显示。
  final double progress;

  /// 章节内滚动比例（0-1），用于本地快速恢复。
  final double chapterProgress;

  final String chapterTitle;
  final String mode;
  final DateTime? updatedAt;

  /// 是否有可恢复的阅读进度
  bool get hasReadableProgress =>
      chapterId.isNotEmpty && (progress > 0 || charOffset > 0);

  /// 转换为可序列化的 Map（用于 API 传输和本地存储）
  Map<String, dynamic> toPayload() {
    return {
      'chapterId': chapterId,
      'charOffset': charOffset,
      'progress': progress,
      'chapterProgress': chapterProgress,
      'chapterTitle': chapterTitle,
      'mode': mode,
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
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
