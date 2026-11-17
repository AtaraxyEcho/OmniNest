part of 'music_controller.dart';

final musicApiProvider = Provider<MusicApi>((ref) {
  return MusicApi(ref.watch(apiClientProvider));
});

/// 提供音乐模块的首页摘要只读视图。
final musicDashboardProvider = FutureProvider<MusicDashboard>((ref) {
  ref.watch(sessionEpochProvider);
  return ref.watch(musicApiProvider).dashboard();
});

/// 收藏曲目分区的数据源：服务端收藏列表。
///
/// 不能由曲库窗口过滤 `favorite` 得到：曲库是分页窗口，窗口之外的收藏永远不出现，
/// 且刷新曲库时会话内的收藏状态变化也要重新取一次才一致。
final musicFavoriteTracksProvider = FutureProvider<List<MusicTrack>>((ref) {
  ref.watch(sessionEpochProvider);
  return ref.watch(musicApiProvider).favorites();
});

final musicPlaybackQueueOwnerIdProvider = FutureProvider<String?>((ref) {
  // 只订阅用户身份：等首帧会话恢复，但仅在 user.id 变化时重建；
  // 同账号 token 静默续期不应重建播放队列归属。
  return ref.watch(
    authSessionProvider.selectAsync((session) => session.user?.id),
  );
});

final musicCenterControllerProvider =
    AsyncNotifierProvider<MusicCenterController, MusicCenterState>(
      MusicCenterController.new,
    );
