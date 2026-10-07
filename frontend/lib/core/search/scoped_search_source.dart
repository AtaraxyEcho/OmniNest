import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 全局搜索的内容档。
///
/// 档标识必须稳定，界面标签另由本地化映射，避免用译文当键导致中英文分叉。
enum ScopedSearchId {
  /// 影视库（服务端关键词）。
  video,

  /// 相册（服务端关键词）。
  photo,

  /// 音乐曲库（当前已加载列表）。
  music,

  /// 文件（当前目录已加载列表）。
  file,

  /// 阅读（服务端关键词，由阅读模块注册）。
  book,
}

/// 单条搜索结果：只带展示字段与直达路由，不携带任何 feature 模型。
///
/// 核心层不得依赖业务模块，因此跨层传递的是这里的中性结构。
class ScopedSearchResult {
  const ScopedSearchResult({
    required this.title,
    required this.detailRoute,
    required this.scope,
    this.subtitle,
  });

  final String title;

  /// 结果行点击后的应用内路由。
  final String detailRoute;
  final ScopedSearchId scope;
  final String? subtitle;
}

/// 覆盖层的结果上限：单档 20 条、合计 60 条。
///
/// 来源按 [perSource] 取一页，聚合层再按 [total] 截断，避免「全部」档
/// 一次性把各档分页拉满。
abstract final class ScopedSearchLimits {
  static const int perSource = 20;
  static const int total = 60;
}

/// 一个内容档的取数来源。
///
/// 实现落在各模块自己的 application 层，由 app 层启动时注册进
/// [ScopedSearchRegistry]，依赖方向始终是 模块 -> core。
abstract class ScopedSearchSource {
  const ScopedSearchSource();

  ScopedSearchId get scope;

  /// 单页查询。[page] 从 0 开始；覆盖层只用自己的分页，不与模块页的
  /// 无限滚动共享状态。
  ///
  /// [ref] 由调用方注入，来源据此读取本模块的仓储或控制器；实现不得
  /// 把 [ref] 保存到字段上，避免跨请求持有已过期的容器。
  Future<List<ScopedSearchResult>> search(
    Ref ref,
    String query, {
    int page = 0,
    CancelToken? cancelToken,
  });
}
