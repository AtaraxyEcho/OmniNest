import 'package:flutter/foundation.dart';

/// 逻辑位置（B8）：跨模式的位置记账事实（章身份 + charOffset 成对）。
///
/// 与 [ReaderPositionSnapshot]（滚动物理位置，绑定布局版本）语义独立：
/// 页模式页进度、恢复登记、章首记账、视觉 seek 落点等没有滚动布局
/// 上下文的位置都记账在此。
@immutable
class ReaderLogicalPosition {
  const ReaderLogicalPosition({
    required this.chapterId,
    required this.charOffset,
  });

  final String chapterId;

  final int charOffset;
}

/// 逻辑位置状态（B8）：页面侧 ReaderPositionTracker 的唯一替代权威。
///
/// 写入只经 [accept]；封面/空章（charOffset 与进度双零）的拦截语义由
/// 调用方持有，本类只做成对记账。
class ReaderLogicalPositionState {
  ReaderLogicalPosition _current = const ReaderLogicalPosition(
    chapterId: '',
    charOffset: 0,
  );

  ReaderLogicalPosition get current => _current;

  /// 当前记账章身份；空串表示尚无任何记账。
  String get chapterId => _current.chapterId;

  /// 当前记账章内字符偏移。
  int get charOffset => _current.charOffset;

  /// 记账一次逻辑位置（章身份与偏移必须成对更新，防止旧章偏移算进
  /// 新章）。
  void accept({required String chapterId, required int charOffset}) {
    _current = ReaderLogicalPosition(
      chapterId: chapterId,
      charOffset: charOffset,
    );
  }
}
