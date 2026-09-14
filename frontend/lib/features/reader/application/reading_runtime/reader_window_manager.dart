/// Window Authority（方案 §41-§42 / §79）：只决定有哪些章节 / 块参与
/// Geometry，不计算进度；位置解释属于 PositionResolver。
///
/// 用户滚动接近窗口边缘时只记录请求（request）；后台 prepare 出
/// Candidate 后在 idle / settling 提交边界进入 Live（方案 §42/§67），
/// 请求与提交必须分离（方案 §148-17）。
class ReaderWindowManager {
  bool pendingForward = false;
  bool pendingBackward = false;

  /// 会话期间挂起的锚点章收养请求（方案 §64）。
  String? pendingChapterId;

  /// 窗口指标是否有未提交变化（迁移自页面 State 的
  /// continuousMetricsDirty，方案 §95）：ACTIVE 期间置位，SETTLING 一次提交。
  bool pendingMetricUpdate = false;

  void requestForward() {
    pendingForward = true;
  }

  void requestBackward() {
    pendingBackward = true;
  }

  void requestChapter(String chapterId) {
    pendingChapterId = chapterId;
  }

  void clearPending() {
    pendingForward = false;
    pendingBackward = false;
    pendingChapterId = null;
  }
}
