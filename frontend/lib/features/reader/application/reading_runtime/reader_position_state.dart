import 'package:omninest/features/reader/application/reading_runtime/reader_position_snapshot.dart';

/// 位置状态（新方案 §29/§30）：transient 随每次物理 offset 解析更新；
/// committed 在事务提交后生成。持久化、离场快照与同步只读 committed。
class ReaderPositionState {
  ReaderPositionSnapshot? _transient;
  ReaderPositionSnapshot? _committed;

  /// 最近一次解析的位置（随滚动逐帧更新）。
  ReaderPositionSnapshot? get transient => _transient;

  /// 最近一次事务提交固化的位置（持久化唯一输入）。
  ReaderPositionSnapshot? get committed => _committed;

  /// 接受一次解析位置（方案 §62 唯一写口 Runtime._acceptPosition）。
  void acceptTransient(ReaderPositionSnapshot snapshot) {
    _transient = snapshot;
  }

  /// 将当前 transient 固化为 committed；无 transient 时保持原值并返回
  /// 现有 committed（可能为 null）。
  ReaderPositionSnapshot? commitTransient() {
    final snapshot = _transient;
    if (snapshot != null) {
      _committed = snapshot;
    }
    return _committed;
  }

  void clear() {
    _transient = null;
    _committed = null;
  }
}
