import 'package:omninest/features/reader/application/reading_runtime/reader_layout_snapshot.dart';

/// 事务种类（方案 §21）：一个 Reader 的每种滚动来源都有显式事务身份。
enum ReaderTransactionKind {
  /// 用户拖动（指针按住且移动超阈值）。
  userDrag,

  /// 鼠标滚轮。
  wheel,

  /// 触控板（高频小 delta）。
  touchpad,

  /// 进度恢复（程序化）。
  restore,

  /// 键盘滚动。
  keyboard,

  /// 章节 / 锚点导航（程序化）。
  navigation,

  /// 视觉进度条拖动 seek（程序化）。
  visualSeek,

  /// 侧边点击翻屏（程序化）。
  sideTap,

  /// 布局修正（滑窗补偿、锚点保持）。
  layoutCorrection,
}

/// 事务阶段（方案 §21）：SETTLING 期间事务必须仍然存在（方案 §37），
/// 直到最终位置 + Geometry Commit + 锚点修正 + 最终解析 + 最终进度全部完成。
enum ReaderTransactionPhase {
  active,

  settling,

  committing,

  completed,

  cancelled,
}

/// 一次阅读滚动/程序化动作的事务对象（方案 §22）。
///
/// 会话期间几何、视口、方向、显示进度与挂起的窗口操作全部属于同一
/// 事务；一个 Reader 实例同一时刻最多一个 active 事务（方案 §23）。
class ReaderTransaction {
  ReaderTransaction({
    required this.id,
    required this.kind,
    required this.layout,
  });

  /// 事务 ID：旧回调按 id 丢弃（方案 §45-46，生产模式同样丢弃）。
  final int id;

  final ReaderTransactionKind kind;

  /// 事务期间唯一可信坐标基准（不可变）。
  final ReaderLayoutSnapshot layout;

  ReaderTransactionPhase phase = ReaderTransactionPhase.active;

  double lastScrollOffset = 0.0;

  double lastVisualProgress = 0.0;

  /// 会话期间挂起的章节收养（方案 §64）：SETTLING 一次提交。
  String? pendingChapterId;

  bool pendingExpandForward = false;

  bool pendingExpandBackward = false;

  /// 本事务是否已完成结束性 Geometry Commit（方案 §68/§107：≤1 次）。
  bool geometryCommitted = false;
}
