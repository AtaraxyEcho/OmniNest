import 'package:omninest/core/realtime/realtime_models.dart';

/// 单个业务作用域的实时失效刷新处理器。
abstract interface class RealtimeScopeHandler {
  /// 处理器负责的业务作用域。
  RealtimeScope get scope;

  /// 判断当前处理器是否消费指定失效记录。
  bool appliesTo(RealtimeInvalidation invalidation);

  /// 刷新该作用域受影响的数据。
  ///
  /// 返回 `false` 表示对应模块尚未激活，失效记录必须保留到后续重试。
  /// 刷新失败时抛出异常，同样保留失效记录。
  Future<bool> refresh(List<RealtimeInvalidation> invalidations);
}

/// 记录处理器已完成的辅助刷新 revision，避免模块未激活时重复请求。
class RealtimeRevisionTracker {
  final Map<String, int> _revisions = <String, int>{};

  /// 返回尚未执行辅助刷新的失效记录。
  List<RealtimeInvalidation> pending(List<RealtimeInvalidation> invalidations) {
    return invalidations
        .where(
          (invalidation) =>
              (_revisions[invalidation.key] ?? 0) < invalidation.revision,
        )
        .toList(growable: false);
  }

  /// 标记辅助刷新完成。
  void markCompleted(Iterable<RealtimeInvalidation> invalidations) {
    for (final invalidation in invalidations) {
      _revisions[invalidation.key] = invalidation.revision;
    }
  }

  /// 在主模块完成刷新后清除临时 revision。
  void clear(Iterable<RealtimeInvalidation> invalidations) {
    for (final invalidation in invalidations) {
      _revisions.remove(invalidation.key);
    }
  }
}
