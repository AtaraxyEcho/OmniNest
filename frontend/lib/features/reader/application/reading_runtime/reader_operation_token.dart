/// Runtime 操作令牌（新方案 §35/§43）：一次 Runtime 异步操作（恢复重试、
/// 程序化滚动、扩窗续作等）的生命周期凭证。在途回调凭 token 判定是否仍
/// 代表当前操作；`mounted` 只表达 Widget 生命周期，二者不可互替（§35）。
class ReaderOperationToken {
  int _generation = 0;

  int get generation => _generation;

  /// 签发当前操作的令牌值。
  int issue() => _generation;

  /// [tokenGeneration] 是否仍代表当前操作。
  bool isCurrent(int tokenGeneration) => tokenGeneration == _generation;

  /// 使所有在途令牌失效，返回新代次。
  int invalidate() => ++_generation;
}
