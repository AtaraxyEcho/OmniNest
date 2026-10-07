import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/search/scoped_search_source.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_track_filter.dart';
import 'package:omninest/features/music/domain/music_models.dart';

/// 音乐档来源：只对已加载曲库做本地过滤。
///
/// 在线源的多平台 loading/failure 状态机仍归甲板自己的搜索页，不并入覆盖层；
/// `/music/tracks` 尚无关键词参数，服务端全库检索要等后端补齐。
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
    // 本地过滤没有分页语义：翻页一律回空，让「加载更多」停止。
    if (page > 0) {
      return const <ScopedSearchResult>[];
    }
    final center = ref.read(musicCenterControllerProvider).asData?.value;
    if (center == null) {
      return const <ScopedSearchResult>[];
    }
    return <ScopedSearchResult>[
      for (final track in filterLoadedTracks(
        center.tracks,
        query,
      ).take(ScopedSearchLimits.perSource))
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
