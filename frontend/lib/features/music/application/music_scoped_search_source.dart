import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/search/scoped_search_source.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';

/// 音乐档来源：走 `/music/search?q=`，服务端按当前用户曲库全量检索。
///
/// 该端点已在 SQL 侧覆盖全库，所以这里不再对已加载列表做本地过滤：本地过滤只
/// 命中已加载窗口，却顶着「音乐」这一档出现，等于承诺大于能力。
/// 在线源的多平台 loading/failure 状态机仍归甲板自己的搜索页，不并入覆盖层。
class MusicScopedSearchSource extends ScopedSearchSource {
  const MusicScopedSearchSource();

  @override
  ScopedSearchId get scope => ScopedSearchId.music;

  @override
  Future<List<ScopedSearchResult>> search(
    Ref ref,
    String query, {
    int page = 0,
    CancelToken? cancelToken,
  }) async {
    final keyword = query.trim();
    if (keyword.isEmpty) {
      return const <ScopedSearchResult>[];
    }
    // 服务端一次返回一页曲目且无翻页语义：第二页起回空，让「加载更多」停止。
    if (page > 0) {
      return const <ScopedSearchResult>[];
    }
    final result = await ref.read(musicApiProvider).search(keyword);
    if (cancelToken?.isCancelled ?? false) {
      return const <ScopedSearchResult>[];
    }
    return <ScopedSearchResult>[
      for (final track in result.tracks)
        ScopedSearchResult(
          title: track.title,
          subtitle: _subtitle(track),
          // 曲目没有独立详情路由，沿用回到音乐空间。
          detailRoute: '/music',
          scope: ScopedSearchId.music,
        ),
    ];
  }

  String? _subtitle(MusicTrack track) {
    final parts = <String>[
      if (track.artistName.isNotEmpty) track.artistName,
      if (track.albumTitle.isNotEmpty) track.albumTitle,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
