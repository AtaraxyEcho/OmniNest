import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/music/data/music_local_preference_store.dart';
import 'package:omninest/features/music/application/music_playback_session.dart';

/// 歌词形态偏好未就绪或读取失败时的设备级默认值。
const bool kMusicLyricScrollModeDefault =
    MusicLocalPreferenceStore.defaultLyricScrollMode;

final musicLocalPreferenceStoreProvider = Provider<MusicLocalPreferenceStore>(
  (ref) => const MusicLocalPreferenceStore(),
);

final musicLocalPreferencesControllerProvider =
    AsyncNotifierProvider<MusicLocalPreferencesController, String>(
      MusicLocalPreferencesController.new,
    );

/// 管理音乐播放的设备级偏好，当前仅包含在线播放音质。
class MusicLocalPreferencesController extends AsyncNotifier<String> {
  @override
  Future<String> build() {
    return ref
        .read(musicLocalPreferenceStoreProvider)
        .loadOnlineQuality()
        .then(
          (value) =>
              value.isEmpty
                  ? MusicLocalPreferenceStore.defaultOnlineQuality
                  : value,
        );
  }

  Future<void> setOnlineQuality(String quality) async {
    await ref
        .read(musicLocalPreferenceStoreProvider)
        .saveOnlineQuality(quality);
    state = AsyncData(quality);
  }

  /// 读取播放倍速（与音质同库存储，控制器主状态仍是音质）。
  Future<double> loadPlaybackSpeed() {
    return ref.read(musicLocalPreferenceStoreProvider).loadPlaybackSpeed();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await ref.read(musicLocalPreferenceStoreProvider).savePlaybackSpeed(speed);
    ref.read(musicPlaybackSessionProvider).player.setRelativePlaySpeed(speed);
  }
}

/// 歌词滚动模式（设备级偏好）：桌面端在编辑视觉中切换，移动端恒用滚动。
/// 独立于跨端同步的视觉设置，避免桌面与窄屏设备互相覆盖。
final musicLyricScrollModeProvider =
    AsyncNotifierProvider<MusicLyricScrollModeController, bool>(
      MusicLyricScrollModeController.new,
    );

class MusicLyricScrollModeController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() {
    return ref.read(musicLocalPreferenceStoreProvider).loadLyricScrollMode();
  }

  Future<void> setScrollMode(bool enabled) async {
    await ref
        .read(musicLocalPreferenceStoreProvider)
        .saveLyricScrollMode(enabled);
    state = AsyncData(enabled);
  }
}

/// 曲目级歌词延迟（设备本地，毫秒）：仅覆盖当前曲目，null 表示未设置，
/// 生效优先级高于全局视觉设置里的 offsetMs。按曲目 family 隔离。
final musicTrackLyricOffsetProvider =
    AsyncNotifierProvider.family<MusicTrackLyricOffsetController, int?, String>(
      MusicTrackLyricOffsetController.new,
    );

class MusicTrackLyricOffsetController extends AsyncNotifier<int?> {
  MusicTrackLyricOffsetController(this.trackId);

  final String trackId;

  @override
  Future<int?> build() {
    return ref
        .read(musicLocalPreferenceStoreProvider)
        .loadLyricOffsetMs(trackId);
  }

  /// 调整该曲目的歌词延迟并写入设备本地存储；范围与全局延迟一致（±1000ms）。
  Future<void> adjust(int deltaMs) async {
    final current = state.asData?.value ?? await future ?? 0;
    final next = (current + deltaMs).clamp(-1000, 1000).toInt();
    state = AsyncData(next);
    await ref
        .read(musicLocalPreferenceStoreProvider)
        .saveLyricOffsetMs(trackId, next);
  }

  /// 清零该曲目的歌词延迟（用户在歌词列头部点击重置）。
  Future<void> resetToZero() async {
    state = const AsyncData(0);
    await ref
        .read(musicLocalPreferenceStoreProvider)
        .saveLyricOffsetMs(trackId, 0);
  }
}
