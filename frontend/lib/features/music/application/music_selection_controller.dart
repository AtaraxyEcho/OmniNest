import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';

/// 批量操作单曲结果。
class MusicBatchItemResult {
  const MusicBatchItemResult({
    required this.trackId,
    required this.title,
    required this.success,
    this.errorMessage,
  });

  final String trackId;
  final String title;
  final bool success;
  final String? errorMessage;
}

/// 曲库多选状态：选中曲目 id 集合与多选开关。
class MusicSelectionState {
  const MusicSelectionState({
    this.selectionMode = false,
    this.selectedIds = const <String>{},
  });

  final bool selectionMode;
  final Set<String> selectedIds;

  bool get hasSelection => selectedIds.isNotEmpty;

  MusicSelectionState copyWith({
    bool? selectionMode,
    Set<String>? selectedIds,
  }) {
    return MusicSelectionState(
      selectionMode: selectionMode ?? this.selectionMode,
      selectedIds: selectedIds ?? this.selectedIds,
    );
  }
}

final musicSelectionControllerProvider =
    NotifierProvider.autoDispose<MusicSelectionController, MusicSelectionState>(
      MusicSelectionController.new,
    );

/// 曲库批量选择控制器：进入/退出多选、单选切换、全选与清空。
class MusicSelectionController extends Notifier<MusicSelectionState> {
  @override
  MusicSelectionState build() {
    return const MusicSelectionState();
  }

  void enterSelectionMode(String trackId) {
    state = state.copyWith(selectionMode: true, selectedIds: {trackId});
  }

  void exitSelectionMode() {
    state = state.copyWith(selectionMode: false, selectedIds: const <String>{});
  }

  void toggle(String trackId) {
    final next = <String>{...state.selectedIds};
    if (!next.remove(trackId)) {
      next.add(trackId);
    }
    state = state.copyWith(selectedIds: next);
  }

  void selectAll(Iterable<String> trackIds) {
    state = state.copyWith(
      selectionMode: true,
      selectedIds: <String>{...trackIds},
    );
  }

  /// 批量加入歌单：逐项执行并返回逐项结果。
  Future<List<MusicBatchItemResult>> addSelectedToPlaylist(
    MusicPlaylist playlist,
    List<MusicTrack> tracks,
  ) async {
    final selected = _selectedTracks(tracks);
    final notifier = ref.read(musicCenterControllerProvider.notifier);
    final results = <MusicBatchItemResult>[];
    for (final track in selected) {
      try {
        await notifier.addTrackToPlaylist(playlist, track);
        results.add(
          MusicBatchItemResult(
            trackId: track.id,
            title: track.title,
            success: true,
          ),
        );
      } on Exception catch (error) {
        results.add(
          MusicBatchItemResult(
            trackId: track.id,
            title: track.title,
            success: false,
            errorMessage: error.toString(),
          ),
        );
      }
    }
    return results;
  }

  /// 批量下一首播放：逐项入队并返回逐项结果。
  List<MusicBatchItemResult> enqueueSelected(List<MusicTrack> tracks) {
    final selected = _selectedTracks(tracks);
    final notifier = ref.read(musicCenterControllerProvider.notifier);
    return [
      for (final track in selected)
        () {
          notifier.enqueue(MusicPlayableItem.local(track));
          return MusicBatchItemResult(
            trackId: track.id,
            title: track.title,
            success: true,
          );
        }(),
    ];
  }

  List<MusicTrack> _selectedTracks(List<MusicTrack> tracks) {
    final ids = state.selectedIds;
    return tracks.where((track) => ids.contains(track.id)).toList();
  }
}
