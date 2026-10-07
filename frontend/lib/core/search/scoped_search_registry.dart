import 'package:omninest/core/search/scoped_search_source.dart';

/// 内容档来源注册表。
///
/// 与顶栏搜索焦点注册表同形态：进程内单例、注册幂等（同档重复注册替换旧值）。
/// 实现由各模块在自己的 application 层提供，由 app 层启动时登记，核心层因此
/// 不需要知道任何业务模块的存在。未登记的档在覆盖层里直接不出现，不预留空档。
abstract final class ScopedSearchRegistry {
  static final Map<ScopedSearchId, ScopedSearchSource> _sources =
      <ScopedSearchId, ScopedSearchSource>{};

  /// 登记一个来源；同档重复登记只保留最后一次，便于测试替换实现。
  static void register(ScopedSearchSource source) {
    _sources[source.scope] = source;
  }

  static ScopedSearchSource? lookup(ScopedSearchId scope) => _sources[scope];

  /// 按 [ScopedSearchId] 声明顺序返回已登记来源，保证「全部」档分组次序稳定。
  static List<ScopedSearchSource> get sources {
    return <ScopedSearchSource>[
      for (final scope in ScopedSearchId.values)
        if (_sources[scope] case final source?) source,
    ];
  }

  /// 仅供测试清理进程内状态。
  static void clearForTest() => _sources.clear();
}
