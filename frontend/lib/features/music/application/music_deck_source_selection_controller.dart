import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';

final musicDeckSourceSelectionProvider =
    NotifierProvider<MusicDeckSourceSelectionController, Set<MusicPlatform>>(
      MusicDeckSourceSelectionController.new,
    );

/// 维护 Music Deck 在应用顶部栏和内容区之间共享的来源筛选状态。
class MusicDeckSourceSelectionController extends Notifier<Set<MusicPlatform>> {
  Set<MusicPlatform> _knownAvailable = const <MusicPlatform>{
    MusicPlatform.local,
  };

  @override
  Set<MusicPlatform> build() {
    final initialPlatform =
        ref.read(musicPlatformLibraryProvider).asData?.value;
    final initialSources =
        initialPlatform == null
            ? const <MusicPlatform>{MusicPlatform.local}
            : _availableSources(initialPlatform);
    _knownAvailable = Set<MusicPlatform>.unmodifiable(initialSources);
    ref.listen(musicPlatformLibraryProvider, (previous, next) {
      final platform = next.asData?.value;
      if (platform != null) {
        synchronize(_availableSources(platform));
      }
    });
    return Set<MusicPlatform>.unmodifiable(initialSources);
  }

  /// 切换单个音乐来源。
  void toggle(MusicPlatform source) {
    final next = <MusicPlatform>{...state};
    if (!next.remove(source)) {
      next.add(source);
    }
    state = Set<MusicPlatform>.unmodifiable(next);
  }

  /// 同步当前可用来源，自动选中新连接的平台并移除已断开的平台。
  void synchronize(Set<MusicPlatform> available) {
    final normalized = <MusicPlatform>{MusicPlatform.local, ...available};
    final added = normalized.difference(_knownAvailable);
    final removed = _knownAvailable.difference(normalized);
    _knownAvailable = Set<MusicPlatform>.unmodifiable(normalized);
    final next = <MusicPlatform>{...state, ...added}..removeAll(removed);
    if (_sameSources(state, next)) {
      return;
    }
    state = Set<MusicPlatform>.unmodifiable(next);
  }

  Set<MusicPlatform> _availableSources(MusicPlatformLibraryState platform) {
    return <MusicPlatform>{
      MusicPlatform.local,
      for (final status in platform.connectedStatuses)
        MusicPlatform.fromApiValue(status.platform),
    };
  }

  bool _sameSources(Set<MusicPlatform> left, Set<MusicPlatform> right) {
    return left.length == right.length && left.containsAll(right);
  }
}
