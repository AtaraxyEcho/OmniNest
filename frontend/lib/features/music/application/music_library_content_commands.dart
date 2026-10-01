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
      final page =
          current.tracks.length ~/ MusicCenterController.musicLibraryPageSize;
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
        ..addAll(result.items.where((track) => knownIds.add(track.id)));
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

  /// 列表投影不带歌词：编辑页等打开时按需补拉完整曲目并回写中心状态。
  ///
  /// 已有歌词时直接返回本地投影；失败时返回已知摘要并写入 errorMessage。
  Future<MusicTrack?> ensureTrackDetail(String trackId) async {
    final current = _currentState;
    MusicTrack? known;
    if (current != null) {
      known =
          _findTrack(current.tracks, trackId) ??
          _findTrack(current.selectedPlaylistTracks, trackId) ??
          _findTrack(current.selectedAlbumTracks, trackId) ??
          _findTrack(current.selectedArtistTracks, trackId) ??
          _findTrack(current.playbackQueue, trackId);
    }
    if (known?.lyricsRaw?.isNotEmpty == true) {
      return known;
    }
    try {
      final detail = await _api.trackDetail(trackId);
      if (_controllerDisposed) {
        return detail;
      }
      _mergeTrackDetail(detail);
      return detail;
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
      return known;
    }
  }

  /// 更新本地曲目元数据，并在需要时先上传自定义封面。
  ///
  /// [clearCover] 为 true 时显式清空封面（与 [coverBytes] 互斥，新封面优先）；
  /// [lyricsRaw] 传空字符串表示清空歌词。
  Future<void> updateTrackMetadata({
    required String trackId,
    required String title,
    String? artistName,
    String? albumTitle,
    String? genre,
    String? lyricsRaw,
    List<int>? coverBytes,
    String? coverFileName,
    bool clearCover = false,
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
        clearCover: clearCover && coverBytes == null,
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

  /// 更新自定义歌单。[clearCover] 为 true 时显式清空封面（新封面优先）。
  Future<void> updatePlaylist(
    MusicPlaylist playlist, {
    required String name,
    String? description,
    List<int>? coverBytes,
    String? coverFileName,
    bool clearCover = false,
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
        clearCover: clearCover && coverBytes == null,
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

  /// 打开歌单详情并加载曲目首页；余下曲目滚动加载。
  Future<void> openPlaylist(MusicPlaylist playlist) async {
    final current = _currentState;
    if (current == null) {
      return;
    }
    try {
      final page = await _api.playlistTracksPage(playlist.id);
      _replaceState(
        current.copyWith(
          section: MusicSection.playlistDetail,
          selectedPlaylist: playlist,
          selectedPlaylistTracks: page.items,
          detailPaging: MusicDetailPaging(
            page: page.page,
            hasMore: page.hasMore,
          ),
        ),
      );
    } on Exception catch (error) {
      _setError(describeUserFacingError(error).message);
      rethrow;
    }
  }

  /// 歌单详情续页：以曲目 id 去重追加，门闩经状态回写，失败回滚。
  Future<void> loadMorePlaylistTracks() async {
    final current = _currentState;
    if (current == null || current.selectedPlaylist == null) {
      return;
    }
    final paging = current.detailPaging;
    if (!paging.hasMore || paging.loadingMore) {
      return;
    }
    _replaceState(
      current.copyWith(detailPaging: paging.copyWith(loadingMore: true)),
    );
    try {
      final next = await _api.playlistTracksPage(
        current.selectedPlaylist!.id,
        page: paging.page + 1,
      );
      final latest = _currentState;
      if (latest == null) {
        return;
      }
      final seen =
          latest.selectedPlaylistTracks.map((track) => track.id).toSet();
      _replaceState(
        latest.copyWith(
          selectedPlaylistTracks: <MusicTrack>[
            ...latest.selectedPlaylistTracks,
            ...next.items.where((track) => !seen.contains(track.id)),
          ],
          detailPaging: MusicDetailPaging(
            page: next.page,
            hasMore: next.hasMore,
          ),
        ),
      );
    } on Exception {
      final latest = _currentState;
      if (latest != null) {
        _replaceState(latest.copyWith(detailPaging: paging));
      }
    }
  }

  /// 播放前确保歌单曲目全量：播放队列按来源全量重建，滚动窗口不够。
  Future<List<MusicTrack>> ensureCompletePlaylistTracks() async {
    final state = _currentState;
    if (state == null) {
      return const <MusicTrack>[];
    }
    if (!state.detailPaging.hasMore || state.selectedPlaylist == null) {
      return state.selectedPlaylistTracks;
    }
    final all = await _api.playlistTracks(state.selectedPlaylist!.id);
    _replaceState(
      state.copyWith(
        selectedPlaylistTracks: all,
        detailPaging: const MusicDetailPaging(),
      ),
    );
    return all;
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

  /// 打开专辑详情并加载曲目首页（失败回退已加载页过滤子集）。
  Future<void> openAlbum(MusicAlbum album) async {
    final current = _currentState;
    if (current == null) {
      return;
    }
    var albumTracks =
        current.tracks
            .where((track) => track.albumTitle == album.title)
            .toList();
    var paging = const MusicDetailPaging();
    try {
      final fetched = await _api.albumTracksPage(album.id);
      if (fetched.items.isNotEmpty) {
        albumTracks = fetched.items;
        paging = MusicDetailPaging(
          page: fetched.page,
          hasMore: fetched.hasMore,
        );
      }
    } on Exception {
      // 首页拉取失败时回退客户端过滤子集。
    }
    _replaceState(
      current.copyWith(
        section: MusicSection.albumDetail,
        selectedAlbum: album,
        selectedAlbumTracks: albumTracks,
        detailPaging: paging,
      ),
    );
  }

  /// 专辑详情续页：以曲目 id 去重追加，门闩经状态回写，失败回滚。
  Future<void> loadMoreAlbumTracks() async {
    final current = _currentState;
    if (current == null || current.selectedAlbum == null) {
      return;
    }
    final paging = current.detailPaging;
    if (!paging.hasMore || paging.loadingMore) {
      return;
    }
    _replaceState(
      current.copyWith(detailPaging: paging.copyWith(loadingMore: true)),
    );
    try {
      final next = await _api.albumTracksPage(
        current.selectedAlbum!.id,
        page: paging.page + 1,
      );
      final latest = _currentState;
      if (latest == null) {
        return;
      }
      final seen = latest.selectedAlbumTracks.map((track) => track.id).toSet();
      _replaceState(
        latest.copyWith(
          selectedAlbumTracks: <MusicTrack>[
            ...latest.selectedAlbumTracks,
            ...next.items.where((track) => !seen.contains(track.id)),
          ],
          detailPaging: MusicDetailPaging(
            page: next.page,
            hasMore: next.hasMore,
          ),
        ),
      );
    } on Exception {
      final latest = _currentState;
      if (latest != null) {
        _replaceState(latest.copyWith(detailPaging: paging));
      }
    }
  }

  /// 播放前确保专辑曲目全量：播放队列按来源全量重建。
  Future<List<MusicTrack>> ensureCompleteAlbumTracks() async {
    final state = _currentState;
    if (state == null) {
      return const <MusicTrack>[];
    }
    if (!state.detailPaging.hasMore || state.selectedAlbum == null) {
      return state.selectedAlbumTracks;
    }
    final all = await _api.albumTracks(state.selectedAlbum!.id);
    _replaceState(
      state.copyWith(
        selectedAlbumTracks: all,
        detailPaging: const MusicDetailPaging(),
      ),
    );
    return all;
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

  /// 打开歌手详情并加载曲目首页（失败回退已加载页过滤子集）。
  Future<void> openArtist(MusicArtist artist) async {
    final current = _currentState;
    if (current == null) {
      return;
    }
    var artistTracks =
        current.tracks
            .where((track) => track.artistName == artist.name)
            .toList();
    var artistPaging = const MusicDetailPaging();
    try {
      final fetched = await _api.artistTracksPage(artist.id);
      if (fetched.items.isNotEmpty) {
        artistTracks = fetched.items;
        artistPaging = MusicDetailPaging(
          page: fetched.page,
          hasMore: fetched.hasMore,
        );
      }
    } on Exception {
      // 首页拉取失败时回退客户端过滤子集。
    }
    _replaceState(
      current.copyWith(
        section: MusicSection.artistDetail,
        selectedArtist: artist,
        selectedArtistTracks: artistTracks,
        detailPaging: artistPaging,
      ),
    );
  }

  /// 歌手详情续页：以曲目 id 去重追加，门闩经状态回写，失败回滚。
  Future<void> loadMoreArtistTracks() async {
    final current = _currentState;
    if (current == null || current.selectedArtist == null) {
      return;
    }
    final paging = current.detailPaging;
    if (!paging.hasMore || paging.loadingMore) {
      return;
    }
    _replaceState(
      current.copyWith(
        selectedArtistTracks: current.selectedArtistTracks,
        detailPaging: paging.copyWith(loadingMore: true),
      ),
    );
    try {
      final next = await _api.artistTracksPage(
        current.selectedArtist!.id,
        page: paging.page + 1,
      );
      final latest = _currentState;
      if (latest == null) {
        return;
      }
      final seen = latest.selectedArtistTracks.map((track) => track.id).toSet();
      _replaceState(
        latest.copyWith(
          selectedArtistTracks: <MusicTrack>[
            ...latest.selectedArtistTracks,
            ...next.items.where((track) => !seen.contains(track.id)),
          ],
          detailPaging: MusicDetailPaging(
            page: next.page,
            hasMore: next.hasMore,
          ),
        ),
      );
    } on Exception {
      final latest = _currentState;
      if (latest != null) {
        _replaceState(latest.copyWith(detailPaging: paging));
      }
    }
  }

  /// 播放前确保歌手曲目全量：播放队列按来源全量重建。
  Future<List<MusicTrack>> ensureCompleteArtistTracks() async {
    final state = _currentState;
    if (state == null) {
      return const <MusicTrack>[];
    }
    if (!state.detailPaging.hasMore || state.selectedArtist == null) {
      return state.selectedArtistTracks;
    }
    final all = await _api.artistTracks(state.selectedArtist!.id);
    _replaceState(
      state.copyWith(
        selectedArtistTracks: all,
        detailPaging: const MusicDetailPaging(),
      ),
    );
    return all;
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
