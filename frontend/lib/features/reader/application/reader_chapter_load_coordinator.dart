/// 章节内容加载协调器。
///
/// 统一维护加载代次、当前请求与失败章节，避免过期异步请求覆盖当前章节。
class ReaderChapterLoadCoordinator {
  int _generation = 0;
  String? _loadingChapterId;
  String? _failedChapterId;

  /// 当前是否正在加载章节内容。
  bool get isLoading => _loadingChapterId != null;

  /// 当前正在加载的章节 ID。
  String? get loadingChapterId => _loadingChapterId;

  /// 判断指定章节是否处于失败状态。
  bool hasFailed(String chapterId) => _failedChapterId == chapterId;

  /// 开始加载并返回本次请求代次。
  int begin(String chapterId) {
    _generation++;
    _loadingChapterId = chapterId;
    _failedChapterId = null;
    return _generation;
  }

  /// 判断异步结果是否仍属于当前请求。
  bool isCurrent(int generation, String chapterId) =>
      generation == _generation && _loadingChapterId == chapterId;

  /// 标记当前请求成功。
  void succeed(int generation, String chapterId) {
    if (!isCurrent(generation, chapterId)) {
      return;
    }
    _loadingChapterId = null;
    _failedChapterId = null;
  }

  /// 标记当前请求失败。
  void fail(int generation, String chapterId) {
    if (!isCurrent(generation, chapterId)) {
      return;
    }
    _loadingChapterId = null;
    _failedChapterId = chapterId;
  }

  /// 清除指定章节的失败状态，允许用户重试。
  void clearFailure(String chapterId) {
    if (_failedChapterId == chapterId) {
      _failedChapterId = null;
    }
  }

  /// 取消当前请求并使在途结果失效。
  void cancel() {
    _generation++;
    _loadingChapterId = null;
  }

  /// 请求结果不再被消费（章节已被切走或收养改写）时释放占用。
  ///
  /// 仅当代次与章节仍匹配时生效，避免误清后续请求的占用状态。
  /// 残留的 _loadingChapterId 会让 isLoading 恒真，进而把依赖该状态的
  /// 输入闸门（如翻页 PagedState.isPaginating）永久锁死。
  void releaseIfCurrent(int generation, String chapterId) {
    if (!isCurrent(generation, chapterId)) {
      return;
    }
    cancel();
  }
}
