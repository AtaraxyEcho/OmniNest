import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/music/domain/music_models.dart';

/// 艺人专辑 shelf 状态：按艺人 id 缓存的专辑列表。
class MusicArtistAlbumsState {
  const MusicArtistAlbumsState({
    this.albumsByArtist = const <String, List<MusicAlbum>>{},
    this.loadingArtistId,
    this.errorMessage,
  });

  final Map<String, List<MusicAlbum>> albumsByArtist;
  final String? loadingArtistId;
  final String? errorMessage;

  MusicArtistAlbumsState copyWith({
    Map<String, List<MusicAlbum>>? albumsByArtist,
    String? loadingArtistId,
    bool clearLoading = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return MusicArtistAlbumsState(
      albumsByArtist: albumsByArtist ?? this.albumsByArtist,
      loadingArtistId:
          clearLoading ? null : (loadingArtistId ?? this.loadingArtistId),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final musicArtistAlbumsControllerProvider = NotifierProvider.autoDispose<
  MusicArtistAlbumsController,
  MusicArtistAlbumsState
>(MusicArtistAlbumsController.new);

/// 拉取艺人专辑：同一艺人结果在会话内缓存，切换详情时避免重复请求。
class MusicArtistAlbumsController extends Notifier<MusicArtistAlbumsState> {
  @override
  MusicArtistAlbumsState build() {
    return const MusicArtistAlbumsState();
  }

  /// 保证指定艺人的专辑已加载；已加载或加载中时跳过。
  Future<void> ensureLoaded(String artistId) async {
    final current = state;
    if (current.albumsByArtist.containsKey(artistId) ||
        current.loadingArtistId == artistId) {
      return;
    }
    state = current.copyWith(loadingArtistId: artistId, clearError: true);
    try {
      final albums = await ref.read(musicApiProvider).artistAlbums(artistId);
      final latest = state;
      final next = <String, List<MusicAlbum>>{
        ...latest.albumsByArtist,
        artistId: albums,
      };
      state = latest.copyWith(albumsByArtist: next, clearLoading: true);
    } on Exception catch (error) {
      final latest = state;
      state = latest.copyWith(
        clearLoading: true,
        errorMessage: describeUserFacingError(error).message,
      );
    }
  }
}
