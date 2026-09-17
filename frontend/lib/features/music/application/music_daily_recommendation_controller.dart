import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_deck_source_selection_controller.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';

final musicDailyRecommendationProvider = AsyncNotifierProvider<
  MusicDailyRecommendationController,
  DailyRecommendedTracks?
>(MusicDailyRecommendationController.new);

/// 按网易云登录状态和来源筛选加载每日推荐歌曲。
class MusicDailyRecommendationController
    extends AsyncNotifier<DailyRecommendedTracks?> {
  static const String _authenticationExpiredCode = '5004';

  @override
  Future<DailyRecommendedTracks?> build() async {
    // 只订阅"网易云推荐是否可见"这一布尔结果，避免平台曲库其它
    // 字段（歌单/喜欢曲目缓存）变化时连带重建本 provider。
    final neteaseVisible = ref.watch(
      musicPlatformLibraryProvider.select((async) {
        final statuses = async.asData?.value.statuses;
        if (statuses == null) {
          return false;
        }
        for (final status in statuses) {
          if (status.platform == MusicPlatform.netease.apiValue) {
            return status.enabled &&
                status.connected &&
                status.capabilities.dailyRecommendations;
          }
        }
        return false;
      }),
    );
    final sources = ref.watch(musicDeckSourceSelectionProvider);
    final visible = neteaseVisible && sources.contains(MusicPlatform.netease);
    if (!visible) {
      return null;
    }
    try {
      return await ref
          .read(musicApiProvider)
          .platformDailyRecommendedTracks(MusicPlatform.netease.apiValue);
    } on Object catch (exception) {
      if (describeUserFacingError(exception).code ==
          _authenticationExpiredCode) {
        unawaited(
          Future<void>.microtask(
            () => ref.invalidate(musicPlatformLibraryProvider),
          ),
        );
      }
      rethrow;
    }
  }

  /// 重试加载当前可见的每日推荐歌曲。
  void retry() {
    ref.invalidateSelf();
  }
}
