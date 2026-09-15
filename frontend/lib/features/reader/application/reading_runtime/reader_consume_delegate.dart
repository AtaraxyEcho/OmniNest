import 'package:omninest/features/reader/application/reading_runtime/reader_position_snapshot.dart';

/// 消费管线页面供给接口（B3 §6.1）。
///
/// Runtime 内化 consume 四步（onPhysicalOffsetChanged → _acceptPosition →
/// _updateVisualProgress / _updateWindowIntent / _confirmLogicalPosition）后，
/// 仍需页面持有的数据（loader 字数、测高收敛态、章内进度）与页面保留的
/// 动作（tracker 写入、持久化调度、收养/扩窗/预取）经本接口注入；
/// Runtime 不反向依赖 Widget 树。
abstract interface class ReaderConsumeDelegate {
  /// 章节总字符数（loader 未就绪时为 0）。
  int totalCharsOf(String chapterId);

  /// 章节测高是否仍在收敛（估算→精测分批替换期间）。
  bool isChapterHeightConverging(String chapterId);

  /// 滚动活动时提前收起「返回原进度」浮层。
  void dismissReturnControl();

  /// 零字符章（封面/图片章）尾部直达预取，保留原分支的窗口 50% 守卫。
  void preloadAdjacentAtTail();

  /// 尾部节流预取（原页面 _throttledPreloadAdjacent）。
  void preloadAdjacentThrottled();

  /// 顺序滚动锚点章收养（原 adoptContinuousAnchorChapter）。
  void adoptChapter(String chapterId);

  /// 空事务期间的节流扩窗（原 _throttledExpandForward/Backward）。
  void expandWindow({required bool forward});

  /// 应用一次位置事实：tracker 更新与调试日志由页面实现。
  void confirmAppliedPosition({
    required ReaderPositionSnapshot snapshot,
    required int totalChars,
  });

  /// 持久化调度（页面实现：scrollProgress 赋值 + 本地保存合并）。
  void persistProgress({
    required String chapterId,
    required int charOffset,
    required double chapterProgress,
  });

  /// 无事务帧的视觉进度兜底（原 bookVisualProgressFor）。
  double visualProgressFallback(String chapterId, double chapterVisualCursor);

  /// 确保全书视觉进度表已按当前窗口构建（事务冻结映射的锚点来源）。
  void ensureVisualExtentTable();

  /// 当前章内进度（页面显示值，收敛抑制与阈值判定用）。
  double get currentChapterProgress;
}
