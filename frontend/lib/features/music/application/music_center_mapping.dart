part of 'music_controller.dart';

extension _MusicCenterMapping on MusicCenterController {
  List<MusicPlayableItem> _toRecentItems(List<MusicRecentEntry> entries) {
    final items = <MusicPlayableItem>[];
    for (final entry in entries) {
      final localTrack = entry.localTrack;
      final onlineTrack = entry.onlineTrack;
      if (localTrack != null) {
        items.add(MusicPlayableItem.local(localTrack));
      } else if (onlineTrack != null) {
        items.add(MusicPlayableItem.online(onlineTrack));
      }
    }
    return List<MusicPlayableItem>.unmodifiable(items);
  }
}

/// 播放模式与持久化快照字段的解码：后端契约仍是 `repeatMode`（off/all/one）
/// 加 `shuffleEnabled` 两个字段，三态互斥只在应用层收敛。
///
/// 随机优先于循环位；旧的 `off`（顺序且到队尾停播）与 `all` 统一归入
/// [MusicPlayMode.sequential]，因为顺序档现在恒为列表首尾循环。
MusicPlayMode _playModeFromSnapshotFields({
  required String repeatMode,
  required bool shuffleEnabled,
}) {
  if (shuffleEnabled) {
    return MusicPlayMode.shuffle;
  }
  return switch (repeatMode) {
    'one' => MusicPlayMode.repeatOne,
    _ => MusicPlayMode.sequential,
  };
}

/// 播放模式到持久化快照字段的编码：与 [_playModeFromSnapshotFields] 互逆。
(String repeatMode, bool shuffleEnabled) _playModeToSnapshotFields(
  MusicPlayMode playMode,
) {
  return switch (playMode) {
    MusicPlayMode.sequential => ('all', false),
    MusicPlayMode.shuffle => ('off', true),
    MusicPlayMode.repeatOne => ('one', false),
  };
}
