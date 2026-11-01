import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/core/errors/error_message.dart';
import 'package:omninest/features/music/domain/music_models.dart';

/// 艺人专辑 shelf 状态：按艺人 id 缓存的专辑列表。
class MusicArtistAlbumsState {
  const MusicArtistAlbumsState({
    this.albumsByArtist = const <String, List<MusicAlbum>>{},
    this.loadingArtistIds = const <String>{},
    this.errorMessage,
  });

  final Map<String, List<MusicAlbum>> albumsByArtist;

  /// 按艺人记录加载态：同时展开两个艺人时，先返回的一个不能把另一个的加载态清掉。
  final Set<String> loadingArtistIds;
  final String? errorMessage;

  MusicArtistAlbumsState copyWith({
    Map<String, List<MusicAlbum>>? albumsByArtist,
    Set<String>? loadingArtistIds,
    String? errorMessage,
    bool clearError = false,
  }) {
    return MusicArtistAlbumsState(
      albumsByArtist: albumsByArtist ?? this.albumsByArtist,
      loadingArtistIds: loadingArtistIds ?? this.loadingArtistIds,
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
        current.loadingArtistIds.contains(artistId)) {
      return;
    }
    state = current.copyWith(
      loadingArtistIds: {...current.loadingArtistIds, artistId},
      clearError: true,
    );
    try {
      final albums = await ref.read(musicApiProvider).artistAlbums(artistId);
      if (!ref.mounted) {
        return;
      }
      final latest = state;
      state = latest.copyWith(
        albumsByArtist: {...latest.albumsByArtist, artistId: albums},
        loadingArtistIds: {...latest.loadingArtistIds}..remove(artistId),
      );
    } on Exception catch (error) {
      if (!ref.mounted) {
        return;
      }
      final latest = state;
      state = latest.copyWith(
        loadingArtistIds: {...latest.loadingArtistIds}..remove(artistId),
        errorMessage: describeUserFacingError(error).message,
      );
    }
  }
}
