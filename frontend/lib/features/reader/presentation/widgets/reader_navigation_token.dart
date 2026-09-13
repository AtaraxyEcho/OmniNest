/// 阅读器显式导航来源。
enum ReaderNavigationSource {
  /// 目录点击。
  tableOfContents,

  /// 上一章/下一章步进。
  chapterStep,

  /// 进度条拖动或进度快照定位。
  progressSeek,

  /// 锚点链接跳转。
  anchorJump,

  /// 返回原进度或远端进度浮层。
  returnToProgress,
}

/// 一次显式章节导航的令牌。
///
/// 显式导航（目录/步进/进度/锚点/返回原进度）创建新令牌并使旧令牌失效；
/// 跨章收养（FlowAdoption）与后台预取不创建令牌。旧任务 ≠ 当前任务：
/// 任何异步结果回写阅读位置前必须校验令牌仍然有效，取消不是正确性的
/// 保障，令牌校验才是。
class ReaderNavigationToken {
  const ReaderNavigationToken._({
    required this.id,
    required this.source,
    required this.targetChapterId,
  });

  /// 单调递增的导航序号。
  final int id;

  /// 导航来源。
  final ReaderNavigationSource source;

  /// 导航目标章节。
  final String targetChapterId;

  @override
  String toString() =>
      'ReaderNavigationToken(#$id, ${source.name}, $targetChapterId)';
}

/// 导航令牌持有者：同一时刻至多一个有效令牌，新导航使旧令牌失效。
class ReaderNavigationTokenHolder {
  ReaderNavigationToken? _current;
  int _sequence = 0;

  /// 当前有效令牌；尚无显式导航时为 null。
  ReaderNavigationToken? get current => _current;

  /// 开始一次新的显式导航：创建令牌并立即使旧令牌失效。
  ReaderNavigationToken begin({
    required ReaderNavigationSource source,
    required String targetChapterId,
  }) {
    final token = ReaderNavigationToken._(
      id: ++_sequence,
      source: source,
      targetChapterId: targetChapterId,
    );
    _current = token;
    return token;
  }

  /// [token] 是否仍是当前有效令牌；null 恒为无效。
  bool isActive(ReaderNavigationToken? token) {
    return token != null && identical(token, _current);
  }

  /// 自捕获 [token]（可为 null，表示尚未发生显式导航）以来是否没有
  /// 新的显式导航介入。恢复类异步流程用它判断"期间导航未变"，
  /// 语义与 [isActive] 不同：null 对 null 视为未变。
  bool isUnchangedSince(ReaderNavigationToken? token) {
    return identical(_current, token);
  }
}
