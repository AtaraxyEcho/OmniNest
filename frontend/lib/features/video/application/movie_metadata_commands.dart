import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/video/application/movie_providers.dart';
import 'package:omninest/features/video/data/movie_api.dart';

/// 影片元数据编辑的应用层入口。
final movieMetadataCommandsProvider = Provider<MovieMetadataCommands>((ref) {
  return MovieMetadataCommands(ref.watch(movieApiProvider));
});

/// 提交影片元数据修改。
///
/// 抽屉只负责收集表单与保存态，端点与参数组装收敛在这里；
/// 返回值是后端回写后的条目，调用方可据此刷新详情。
class MovieMetadataCommands {
  const MovieMetadataCommands(this._api);

  final MovieApi _api;

  Future<void> updateMetadata({
    required String videoItemId,
    required String title,
    String? originalTitle,
    DateTime? releaseDate,
    String? overview,
    String? posterFileId,
    String? backdropFileId,
    int? runtimeSeconds,
    String metadataStatus = 'MANUAL',
  }) async {
    await _api.updateMetadata(
      videoItemId: videoItemId,
      title: title,
      originalTitle: originalTitle,
      releaseDate: releaseDate,
      overview: overview,
      posterFileId: posterFileId,
      backdropFileId: backdropFileId,
      runtimeSeconds: runtimeSeconds,
      metadataStatus: metadataStatus,
    );
  }
}
