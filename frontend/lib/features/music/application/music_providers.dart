part of 'music_controller.dart';

final musicApiProvider = Provider<MusicApi>((ref) {
  return MusicApi(ref.watch(apiClientProvider));
});

/// 提供音乐模块的首页摘要只读视图。
final musicDashboardProvider = FutureProvider<MusicDashboard>((ref) {
  ref.watch(sessionEpochProvider);
  return ref.watch(musicApiProvider).dashboard();
});

final musicPlaybackQueueOwnerIdProvider = FutureProvider<String?>((ref) async {
  final authState = await ref.watch(authSessionProvider.future);
  return authState.user?.id;
});

final musicCenterControllerProvider =
    AsyncNotifierProvider<MusicCenterController, MusicCenterState>(
      MusicCenterController.new,
    );
