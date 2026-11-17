import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/video/application/movie_providers.dart';
import 'package:omninest/features/video/data/movie_api.dart';
import 'package:omninest/features/video/domain/movie_management_models.dart';

/// 详情页的元数据后端动作（重新探测 / 导出 NFO / 按选中候选刮削）。
///
/// 桌面详情页只负责交互与提示，端点与参数组装收敛在这里，避免页面直接依赖
/// `MovieApi` 的具体方法名；测试用接口替身锁定调用。
final movieDetailBackendActionsProvider = Provider<MovieDetailBackendActions>((
  ref,
) {
  return ApiMovieDetailBackendActions(ref.watch(movieApiProvider));
});

abstract interface class MovieDetailBackendActions {
  /// 同步执行 FFprobe 并回写媒体信息；失败由调用方展示错误。
  Future<void> reprobe(String videoItemId);

  /// 生成 NFO 内容并落盘为派生资产，返回导出结果供提示文案使用。
  Future<NfoExport> exportNfo(String videoItemId);

  /// 按用户在候选列表里选中的条目创建刮削任务（force 覆盖既有元数据）。
  Future<ScrapeTask> matchCandidate({
    required String fileNodeId,
    required String provider,
    required String externalId,
  });
}

final class ApiMovieDetailBackendActions implements MovieDetailBackendActions {
  const ApiMovieDetailBackendActions(this._api);

  final MovieApi _api;

  @override
  Future<void> reprobe(String videoItemId) => _api.probeItem(videoItemId);

  @override
  Future<NfoExport> exportNfo(String videoItemId) =>
      _api.exportNfo(videoItemId);

  @override
  Future<ScrapeTask> matchCandidate({
    required String fileNodeId,
    required String provider,
    required String externalId,
  }) {
    return _api.createScrapeTask(
      fileNodeId: fileNodeId,
      force: true,
      provider: provider,
      externalId: externalId,
    );
  }
}
