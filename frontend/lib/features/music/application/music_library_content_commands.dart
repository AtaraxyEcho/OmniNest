part of 'music_controller.dart';

/// 管理音乐曲库内容、歌单和详情导航命令。
extension MusicLibraryContentCommands on MusicCenterController {
  /// 增量加载下一页曲目，按 id 去重后追加并维护分页状态。
  Future<void> loadMoreTracks() async {
    final current = _currentState;
    if (current == null ||
        !current.hasMoreTracks ||
        current.tracksLoadingMore) {
      return;
    }
    _replaceState(current.copyWith(tracksLoadingMore: true));
    final generation = _refreshGeneration;
    try {
      final page = current.tracks.length ~/ MusicCenterController.musicLibraryPageSize;
      final result = await _api.tracks(
        page: page,
        size: MusicCenterController.musicLibraryPageSize,
      );
      if (_controllerDisposed || generation != _refreshGeneration) {
        return;
      }
      final latest = _currentState;
      if (latest == null) {
        return;
      }
      final knownIds = latest.tracks.map((track) => track.id).toSet();
      final merged = List<MusicTrack>.of(latest.tracks)
        ..addAll(
          result.items.where((track) => knownIds.add(track.id)),
        );
      _replaceState(
        latest.copyWith(
          tracks: List<MusicTrack>.unmodifiable(merged),
          hasMoreTracks: result.hasMore,
          tracksLoadingMore: false,
        ),
      );
    } on Exception catch (error) {
      final latest = _currentState;
      if (latest != null && latest.tracksLoadingMore) {
        _replaceState(latest.copyWith(tracksLoadingMore: false));
      }
      _setError(describeUserFacingError(error).message);
    }
  }

  /// 更新本地曲目元数据，并在需要时先上传自定义封面。
  Future<void> updateTrackMetadata({
    required String trackId,
    required String title,
    String? artistName,
    String? albumTitle,
    String? genre,
    String? lyricsRaw,
    List<int>? coverBytes,
    String? coverFileName,
  }) async {
    try {
      final coverFileId =
          coverBytes == null
              ? null
              : await _api.uploadCover(
                bytes: coverBytes,
                fileName: coverFileName ?? 'cover.jpg',
              );
      await _api.updateTrack(
        trackId: trackId,
        title: title,
        artistName: artistName,
        albumTitle: albumTitle,
        genre: genre,
        lyricsRaw: lyricsRaw,
        coverFileId: coverFileId,
      );
      await refresh();
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
      rethrow;
    }
  }

  /// 切换本地曲目的收藏状态。
  Future<void> toggleFavorite(MusicTrack track) async {
    final current = _currentState;
    if (current == null) {
      return;
    }
    try {
      if (track.favorite) {
        await _api.removeFavorite(track.id);
      } else {
        await _api.favorite(track.id);
      }
      List<MusicTrack> patchFavorite(List<MusicTrack> items) {
        return items
            .map(
              (item) =>
                  item.id == track.id
                      ? item.copyWith(favorite: !track.favorite)
                      : item,
            )
            .toList(growable: false);
      }

      final nextCurrentItem =
          current.currentItem?.track.id == track.id
              ? current.currentItem!.copyWith(
                track: current.currentItem!.track.copyWith(
                  favorite: !track.favorite,
                ),
              )
              : current.currentItem;
      _replaceState(
        current.copyWith(
          tracks: patchFavorite(current.tracks),
          selectedPlaylistTracks: patchFavorite(current.selectedPlaylistTracks),
          selectedAlbumTracks: patchFavorite(current.selectedAlbumTracks),
          selectedArtistTracks: patchFavorite(current.selectedArtistTracks),
          currentItem: nextCurrentItem,
        ),
      );
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
      rethrow;
    }
  }

  /// 删除本地曲目并刷新曲库。
  Future<TaskSubmission> deleteTrack(
    MusicTrack track, {
    bool cascade = false,
  }) async {
    try {
      final submission = await _api.deleteTrack(track.id, cascade: cascade);
      if (_currentState?.currentItem?.playableKey == 'local:${track.id}') {
        await setPlaying(false);
      }
      removeFromQueue('local:${track.id}');
      await refresh();
      await _refreshTaskState();
      return submission;
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
      rethrow;
    }
  }

  /// 创建自定义歌单并返回创建结果。
  Future<MusicPlaylist?> createPlaylist({
    required String name,
    String? description,
    List<int>? coverBytes,
    String? coverFileName,
  }) async {
    final current = _currentState;
    if (current == null) {
      return null;
    }
    try {
      final coverFileId =
          coverBytes == null
              ? null
              : await _api.uploadCover(
                bytes: coverBytes,
                fileName: coverFileName ?? 'playlist-cover.jpg',
              );
      final playlist = await _api.createPlaylist(
        name: name,
        description: description,
        coverFileId: coverFileId,
      );
      _replaceState(
        current.copyWith(playlists: [playlist, ...current.playlists]),
      );
      return playlist;
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
      rethrow;
    }
  }

  /// 更新自定义歌单。
  Future<void> updatePlaylist(
    MusicPlaylist playlist, {
    required String name,
    String? description,
    List<int>? coverBytes,
    String? coverFileName,
  }) async {
    final current = _currentState;
    if (current == null) {
      return;
    }
    try {
      final coverFileId =
          coverBytes == null
              ? null
              : await _api.uploadCover(
                bytes: coverBytes,
                fileName: coverFileName ?? 'playlist-cover.jpg',
              );
      final updated = await _api.updatePlaylist(
        playlistId: playlist.id,
        name: name,
        description: description,
        coverFileId: coverFileId,
      );
      _replaceState(
        current.copyWith(
          playlists: current.playlists
              .map((item) => item.id == updated.id ? updated : item)
              .toList(growable: false),
          selectedPlaylist:
              current.selectedPlaylist?.id == updated.id
                  ? updated
                  : current.selectedPlaylist,
        ),
      );
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
      rethrow;
    }
  }

  /// 删除自定义歌单。
  Future<void> deletePlaylist(MusicPlaylist playlist) async {
    final current = _currentState;
    if (current == null) {
      return;
    }
    try {
      await _api.deletePlaylist(playlist.id);
      final removingSelected = current.selectedPlaylist?.id == playlist.id;
      _replaceState(
        current.copyWith(
          playlists:
              current.playlists
                  .where((item) => item.id != playlist.id)
                  .toList(),
          clearSelectedPlaylist: removingSelected,
          section:
              removingSelected ? MusicSection.customPlaylists : current.section,
        ),
      );
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
      rethrow;
    }
  }

  /// 将曲目加入自定义歌单。
  Future<void> addTrackToPlaylist(
    MusicPlaylist playlist,
    MusicTrack track,
  ) async {
    final current = _currentState;
    if (current == null) {
      return;
    }
    try {
      final updated = await _api.addPlaylistItems(playlist.id, [track.id]);
      final isSelectedPlaylist = current.selectedPlaylist?.id == playlist.id;
      final nextSelectedTracks =
          isSelectedPlaylist &&
                  !current.selectedPlaylistTracks.any(
                    (item) => item.id == track.id,
                  )
              ? [...current.selectedPlaylistTracks, track]
              : current.selectedPlaylistTracks;
      _replaceState(
        current.copyWith(
          playlists:
              current.playlists
                  .map((item) => item.id == updated.id ? updated : item)
                  .toList(),
          selectedPlaylist:
              isSelectedPlaylist ? updated : current.selectedPlaylist,
          selectedPlaylistTracks: nextSelectedTracks,
        ),
      );
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
      rethrow;
    }
  }

  /// 打开歌单详情并加载曲目。
  Future<void> openPlaylist(MusicPlaylist playlist) async {
    final current = _currentState;
    if (current == null) {
      return;
    }
    try {
      final tracks = await _api.playlistTracks(playlist.id);
      _replaceState(
        current.copyWith(
          section: MusicSection.playlistDetail,
          selectedPlaylist: playlist,
          selectedPlaylistTracks: tracks,
        ),
      );
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
      rethrow;
    }
  }

  /// 关闭歌单详情。
  void closePlaylist() {
    final current = _currentState;
    if (current == null) {
      return;
    }
    _replaceState(
      current.copyWith(
        section: MusicSection.customPlaylists,
        clearSelectedPlaylist: true,
      ),
    );
  }

  /// 打开专辑详情。
  void openAlbum(MusicAlbum album) {
    final current = _currentState;
    if (current == null) {
      return;
    }
    final albumTracks =
        current.tracks
            .where((track) => track.albumTitle == album.title)
            .toList();
    _replaceState(
      current.copyWith(
        section: MusicSection.albumDetail,
        selectedAlbum: album,
        selectedAlbumTracks: albumTracks,
      ),
    );
  }

  /// 关闭专辑详情。
  void closeAlbum() {
    final current = _currentState;
    if (current == null) {
      return;
    }
    _replaceState(
      current.copyWith(section: MusicSection.albums, clearSelectedAlbum: true),
    );
  }

  /// 打开歌手详情。
  void openArtist(MusicArtist artist) {
    final current = _currentState;
    if (current == null) {
      return;
    }
    final artistTracks =
        current.tracks
            .where((track) => track.artistName == artist.name)
            .toList();
    _replaceState(
      current.copyWith(
        section: MusicSection.artistDetail,
        selectedArtist: artist,
        selectedArtistTracks: artistTracks,
      ),
    );
  }

  /// 关闭歌手详情。
  void closeArtist() {
    final current = _currentState;
    if (current == null) {
      return;
    }
    _replaceState(
      current.copyWith(
        section: MusicSection.artists,
        clearSelectedArtist: true,
      ),
    );
  }

  /// 从当前歌单移除曲目。
  Future<void> removeTrackFromSelectedPlaylist(MusicTrack track) async {
    final current = _currentState;
    final playlist = current?.selectedPlaylist;
    if (current == null || playlist == null) {
      return;
    }
    try {
      final updatedPlaylist = await _api.removePlaylistItems(playlist.id, [
        track.id,
      ]);
      final nextTracks =
          current.selectedPlaylistTracks
              .where((item) => item.id != track.id)
              .toList();
      _replaceState(
        current.copyWith(
          selectedPlaylist: updatedPlaylist,
          selectedPlaylistTracks: nextTracks,
          playlists:
              current.playlists
                  .map(
                    (item) =>
                        item.id == updatedPlaylist.id ? updatedPlaylist : item,
                  )
                  .toList(),
        ),
      );
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
      rethrow;
    }
  }
}
