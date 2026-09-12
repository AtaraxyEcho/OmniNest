import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_deck_search_controller.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/data/music_playback_queue_store.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_search.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

part 'music_controller_platform_test_part.dart';
part 'music_controller_queue_test_part.dart';

void main() {
  test('play track loads playback plan and marks music playing', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);

    await container
        .read(musicCenterControllerProvider.notifier)
        .playTrack(api.track);

    final state = container.read(musicCenterControllerProvider).value!;
    expect(api.playbackPlanTrackIds, ['track-1']);
    expect(api.recordedHistoryKeys, ['local:track-1']);
    expect(state.currentTrack?.id, 'track-1');
    expect(state.playbackPlan?.url, 'http://localhost/track-1.flac');
    expect(state.isPlaying, isTrue);
  });

  test('online temporary track does not request local playback plan', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);

    final controller = container.read(musicCenterControllerProvider.notifier);
    await controller.playOnlineTrack(
      const OnlineTrack(
        platform: 'netease',
        songId: '188888',
        title: 'Cloud Song',
        artistName: 'Online Artist',
        durationSeconds: 180,
      ),
    );
    final onlineTrack =
        container.read(musicCenterControllerProvider).value!.currentTrack!;
    final onlineState = container.read(musicCenterControllerProvider).value!;
    expect(onlineState.currentItem?.ref, isA<OnlineMusicRef>());
    expect(onlineState.currentItem?.playableKey, 'online:netease:188888');

    await controller.playTrack(onlineTrack);
    await controller.playTrack(api.track);

    final state = container.read(musicCenterControllerProvider).value!;
    expect(
      api.playbackPlanTrackIds.where((id) => id.startsWith('online:')),
      isEmpty,
    );
    expect(api.playbackPlanTrackIds.last, 'track-1');
    expect(api.onlinePlaybackRequests, hasLength(1));
    expect(api.recordedHistoryKeys.first, 'online:netease:188888');
    expect(onlineState.recentItems.first.playableKey, 'online:netease:188888');
    expect(state.currentTrack?.id, 'track-1');
    expect(state.isPlaying, isTrue);
  });

  test('startup restores the latest online playable item', () async {
    final api =
        _FakeMusicApi()
          ..recentEntries = [
            MusicRecentEntry(
              playableKey: 'online:netease:188888',
              onlineTrack: const OnlineTrack(
                platform: 'netease',
                songId: '188888',
                title: 'Cloud Song',
                artistName: 'Online Artist',
                coverUrl: 'https://example.com/cloud.jpg',
              ),
              playedAt: DateTime.utc(2026, 7, 12),
            ),
          ];
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    final state = await container.read(musicCenterControllerProvider.future);

    expect(state.currentItem?.playableKey, 'online:netease:188888');
    expect(state.currentTrack?.title, 'Cloud Song');
    expect(state.playbackPlan?.url, 'http://localhost/online-track.mp3');
    expect(api.onlinePlaybackRequests, ['netease:188888:']);
    expect(api.playbackPlanTrackIds, isEmpty);
  });

  registerMusicQueueTests();

  test('scrape library passes force flag and records the job', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);

    await container
        .read(musicCenterControllerProvider.notifier)
        .scrapeLibrary(force: true);
    final state = container.read(musicCenterControllerProvider).asData!.value;

    expect(api.scrapeLibraryForceFlags, [true]);
    expect(state.lastScanJob?.id, 'scrape-job');
    expect(state.lastScanJob?.status, 'COMPLETED');
  });

  test('apply scrape candidate updates track metadata in state', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    const candidate = MusicScrapeCandidate(
      provider: 'netease',
      externalId: '199',
      title: 'Scraped Title',
      artistName: 'Scraped Artist',
      albumTitle: 'Scraped Album',
    );
    api.libraryTracks[0] = const MusicTrack(
      id: 'track-1',
      fileNodeId: 'file-1',
      title: 'Scraped Title',
      artistName: 'Scraped Artist',
      albumTitle: 'Scraped Album',
      format: 'flac',
      favorite: false,
    );

    await container
        .read(musicCenterControllerProvider.notifier)
        .applyScrapeCandidate(api.track, candidate);
    final state = container.read(musicCenterControllerProvider).asData!.value;

    expect(api.appliedScrapeTrackIds, ['track-1']);
    expect(
      state.tracks.where((track) => track.id == 'track-1').single.title,
      'Scraped Title',
    );
  });

  test('loadMoreTracks appends the next page and stops at the end', () async {
    final api = _FakeMusicApi();
    for (var index = 0; index < 148; index++) {
      api.libraryTracks.add(
        MusicTrack(
          id: 'bulk-$index',
          fileNodeId: 'file-bulk-$index',
          title: 'Bulk $index',
          artistName: 'Bulk Artist',
          albumTitle: 'Bulk Album',
          format: 'mp3',
          favorite: false,
        ),
      );
    }
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final state = await container.read(musicCenterControllerProvider.future);

    expect(state.tracks, hasLength(100));
    expect(state.hasMoreTracks, isTrue);

    await container
        .read(musicCenterControllerProvider.notifier)
        .loadMoreTracks();
    final next = container.read(musicCenterControllerProvider).asData!.value;

    expect(next.tracks, hasLength(150));
    expect(next.hasMoreTracks, isFalse);
    expect(next.tracksLoadingMore, isFalse);
    expect(api.tracksPageRequests, [0, 1]);

    await container
        .read(musicCenterControllerProvider.notifier)
        .loadMoreTracks();
    final afterEnd =
        container.read(musicCenterControllerProvider).asData!.value;
    expect(afterEnd.tracks, hasLength(150));
    expect(api.tracksPageRequests, [0, 1]);
  });

  test('refresh keeps incrementally loaded tracks', () async {
    final api = _FakeMusicApi();
    for (var index = 0; index < 148; index++) {
      api.libraryTracks.add(
        MusicTrack(
          id: 'bulk-$index',
          fileNodeId: 'file-bulk-$index',
          title: 'Bulk $index',
          artistName: 'Bulk Artist',
          albumTitle: 'Bulk Album',
          format: 'mp3',
          favorite: false,
        ),
      );
    }
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    await container
        .read(musicCenterControllerProvider.notifier)
        .loadMoreTracks();

    await container.read(musicCenterControllerProvider.notifier).refresh();
    final refreshed =
        container.read(musicCenterControllerProvider).asData!.value;

    expect(refreshed.tracks, hasLength(150));
    expect(refreshed.hasMoreTracks, isFalse);
  });

  test('empty music history does not select the first local track', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);

    final state = await container.read(musicCenterControllerProvider.future);

    expect(state.currentItem, isNull);
    expect(state.activeItem, isNull);
    expect(state.activeTrack, isNull);
  });

  test(
    'unavailable online restore falls back to the latest local track',
    () async {
      final api =
          _FakeMusicApi()
            ..onlinePlaybackError = const AppException(
              code: '5001',
              message: '媒体资源不存在',
            );
      api.recentEntries = [
        MusicRecentEntry(
          playableKey: 'online:netease:deleted-song',
          onlineTrack: const OnlineTrack(
            platform: 'netease',
            songId: 'deleted-song',
            title: 'Deleted Song',
            artistName: 'Online Artist',
          ),
          playedAt: DateTime.utc(2026, 7, 12, 10),
        ),
        MusicRecentEntry(
          playableKey: 'local:track-2',
          localTrack: api.secondTrack,
          playedAt: DateTime.utc(2026, 7, 11, 10),
        ),
      ];
      final container = ProviderContainer.test(
        overrides: [musicApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final state = await container.read(musicCenterControllerProvider.future);

      expect(state.currentItem?.playableKey, 'local:track-2');
      expect(state.playbackPlan?.trackId, 'track-2');
      expect(api.onlinePlaybackRequests, ['netease:deleted-song:']);
      expect(api.playbackPlanTrackIds, ['track-2']);
      expect(state.errorMessage, isNull);
    },
  );

  test(
    'transient online restore failure preserves the online selection',
    () async {
      final api =
          _FakeMusicApi()
            ..onlinePlaybackError = const AppException(
              code: 'REQUEST_TIMEOUT',
              message: '请求超时，请稍后重试',
            )
            ..recentEntries = [
              MusicRecentEntry(
                playableKey: 'online:qq:temporary-song',
                onlineTrack: const OnlineTrack(
                  platform: 'qq',
                  songId: 'temporary-song',
                  title: 'Temporary Song',
                  artistName: 'Online Artist',
                ),
                playedAt: DateTime.utc(2026, 7, 12),
              ),
            ];
      final container = ProviderContainer.test(
        overrides: [musicApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final state = await container.read(musicCenterControllerProvider.future);

      expect(state.currentItem?.playableKey, 'online:qq:temporary-song');
      expect(state.playbackPlan, isNull);
      expect(state.errorMessage, contains('请求超时'));
      expect(api.playbackPlanTrackIds, isEmpty);
    },
  );

  test('online lyrics are merged into the active playable item', () async {
    final api = _FakeMusicApi()..onlineLyrics['188888'] = '[00:01.00]Cloud';
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);

    await container
        .read(musicCenterControllerProvider.notifier)
        .playOnlineTrack(
          const OnlineTrack(
            platform: 'netease',
            songId: '188888',
            title: 'Cloud Song',
            artistName: 'Online Artist',
          ),
        );
    await Future<void>.delayed(Duration.zero);

    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.currentTrack?.lyricsRaw, '[00:01.00]Cloud');
    expect(api.lyricsRequests, ['netease:188888']);
  });

  test(
    'adding track to playlist calls api and updates playlist summary',
    () async {
      final api = _FakeMusicApi();
      final container = ProviderContainer.test(
        overrides: [musicApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      await container.read(musicCenterControllerProvider.future);

      await container
          .read(musicCenterControllerProvider.notifier)
          .addTrackToPlaylist(api.playlist, api.track);

      final state = container.read(musicCenterControllerProvider).value!;
      expect(api.addedPlaylistItems, {
        'playlist-1': ['track-1'],
      });
      expect(state.playlists.single.trackCount, 1);
    },
  );

  test('playlist create and update upload the selected cover first', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    final controller = container.read(musicCenterControllerProvider.notifier);

    await controller.createPlaylist(
      name: 'Focus',
      description: 'Deep work',
      coverBytes: const [1, 2, 3],
      coverFileName: 'focus.png',
    );
    final created =
        container.read(musicCenterControllerProvider).value!.playlists.first;
    await controller.updatePlaylist(
      created,
      name: 'Focus 2',
      description: 'Updated',
      coverBytes: const [4, 5, 6],
      coverFileName: 'focus-2.png',
    );

    final state = container.read(musicCenterControllerProvider).value!;
    expect(api.uploadedCoverNames, ['focus.png', 'focus-2.png']);
    expect(api.createdPlaylistCoverFileId, 'fake-cover-id');
    expect(api.updatedPlaylistCoverFileId, 'fake-cover-id');
    expect(state.playlists.first.name, 'Focus 2');
  });

  test(
    'track metadata command uploads cover and updates through api',
    () async {
      final api = _FakeMusicApi();
      final container = ProviderContainer.test(
        overrides: [musicApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      await container.read(musicCenterControllerProvider.future);

      await container
          .read(musicCenterControllerProvider.notifier)
          .updateTrackMetadata(
            trackId: 'track-1',
            title: 'Updated title',
            artistName: 'Updated artist',
            albumTitle: 'Updated album',
            genre: 'Ambient',
            lyricsRaw: '[00:01.00]Updated lyrics',
            coverBytes: const [1, 2, 3],
            coverFileName: 'updated-cover.png',
          );

      expect(api.uploadedCoverNames, ['updated-cover.png']);
      expect(api.updatedTrackId, 'track-1');
      expect(api.updatedTrackTitle, 'Updated title');
      expect(api.updatedTrackArtistName, 'Updated artist');
      expect(api.updatedTrackAlbumTitle, 'Updated album');
      expect(api.updatedTrackGenre, 'Ambient');
      expect(api.updatedTrackLyricsRaw, '[00:01.00]Updated lyrics');
      expect(api.updatedTrackCoverFileId, 'fake-cover-id');
    },
  );

  test('deleting a custom playlist removes it from state', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);

    await container
        .read(musicCenterControllerProvider.notifier)
        .deletePlaylist(api.playlist);

    expect(api.deletedPlaylistIds, ['playlist-1']);
    expect(
      container.read(musicCenterControllerProvider).value!.playlists,
      isEmpty,
    );
  });

  test('next track advances through playback queue', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);

    final controller = container.read(musicCenterControllerProvider.notifier);
    await controller.playTrack(api.track);
    await controller.nextTrack();

    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.currentTrack?.id, 'track-2');
    expect(state.playbackIndex, 1);
    expect(state.playbackQueue.map((track) => track.id), [
      'track-1',
      'track-2',
    ]);
    expect(api.playbackPlanTrackIds, ['track-1', 'track-2']);
  });

  test(
    'queue keeps local and online playable items in one typed list',
    () async {
      final api = _FakeMusicApi();
      final container = ProviderContainer.test(
        overrides: [musicApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      await container.read(musicCenterControllerProvider.future);

      final controller = container.read(musicCenterControllerProvider.notifier);
      await controller.playTrack(api.track);
      controller.enqueue(
        MusicPlayableItem.online(
          const OnlineTrack(
            platform: 'netease',
            songId: 'song-1',
            title: 'Cloud Song',
            artistName: 'Online Artist',
          ),
        ),
      );
      controller.reorderQueue(2, 0);

      final state = container.read(musicCenterControllerProvider).value!;
      expect(state.playbackItems.map((item) => item.playableKey), [
        'online:netease:song-1',
        'local:track-1',
        'local:track-2',
      ]);
      expect(state.playbackIndex, 1);
    },
  );

  test(
    'unavailable online queue item advances to the next local item',
    () async {
      final api =
          _FakeMusicApi()
            ..onlinePlaybackError = const AppException(
              code: 'MEDIA_NOT_FOUND',
              message: '媒体资源不存在',
            );
      final container = ProviderContainer.test(
        overrides: [musicApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      await container.read(musicCenterControllerProvider.future);

      final onlineItem = MusicPlayableItem.online(
        const OnlineTrack(
          platform: 'netease',
          songId: 'deleted-song',
          title: 'Deleted Song',
          artistName: 'Online Artist',
        ),
      );
      await container.read(musicCenterControllerProvider.notifier).playItems([
        onlineItem,
        MusicPlayableItem.local(api.secondTrack),
      ]);

      final state = container.read(musicCenterControllerProvider).value!;
      expect(state.currentItem?.playableKey, 'local:track-2');
      expect(state.playbackItems.map((item) => item.playableKey), [
        'local:track-2',
      ]);
      expect(state.playbackIndex, 0);
      expect(state.isPlaying, isTrue);
      expect(api.onlinePlaybackRequests, ['netease:deleted-song:']);
      expect(api.playbackPlanTrackIds.last, 'track-2');
    },
  );

  test('late playback plan cannot replace a newer track selection', () async {
    final api = _DelayedMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    api.delayFirstTrack = true;

    final controller = container.read(musicCenterControllerProvider.notifier);
    final oldRequest = controller.playTrack(api.track);
    await controller.playTrack(api.secondTrack);
    api.releaseFirstTrack();
    await oldRequest;

    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.currentTrack?.id, 'track-2');
  });

  test('repeat all wraps next track to queue start', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);

    final controller = container.read(musicCenterControllerProvider.notifier);
    await controller.playTrack(api.secondTrack);
    controller.toggleRepeatMode();
    await controller.nextTrack();

    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.repeatMode, MusicRepeatMode.all);
    expect(state.currentTrack?.id, 'track-1');
    expect(state.isPlaying, isTrue);
  });

  test('shuffle next track skips the current queue item', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);

    final controller = container.read(musicCenterControllerProvider.notifier);
    await controller.playTrack(api.track);
    controller.toggleShuffle();
    await controller.nextTrack();

    final state = container.read(musicCenterControllerProvider).value!;
    expect(state.shuffleEnabled, isTrue);
    expect(state.currentTrack?.id, 'track-2');
    expect(state.playbackIndex, 1);
  });

  test(
    'opening playlist loads tracks and removing track updates detail',
    () async {
      final api = _FakeMusicApi();
      final container = ProviderContainer.test(
        overrides: [musicApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);
      await container.read(musicCenterControllerProvider.future);

      final controller = container.read(musicCenterControllerProvider.notifier);
      await controller.openPlaylist(api.playlist);
      await controller.removeTrackFromSelectedPlaylist(api.track);

      final state = container.read(musicCenterControllerProvider).value!;
      expect(api.loadedPlaylistIds, ['playlist-1']);
      expect(api.removedPlaylistItems, {
        'playlist-1': ['track-1'],
      });
      expect(state.selectedPlaylist?.id, 'playlist-1');
      expect(state.selectedPlaylistTracks.map((track) => track.id), [
        'track-2',
      ]);
      expect(state.playlists.single.trackCount, 1);
    },
  );

  test('deleting track removes it from music state', () async {
    final api = _FakeMusicApi();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);

    await container
        .read(musicCenterControllerProvider.notifier)
        .deleteTrack(api.track);

    final state = container.read(musicCenterControllerProvider).value!;
    expect(api.deletedTrackIds, ['track-1']);
    expect(state.tracks.map((track) => track.id), ['track-2']);
  });

  registerMusicPlatformTests();
}

class _EmptyMusicPlatformLibraryController
    extends MusicPlatformLibraryController {
  @override
  Future<MusicPlatformLibraryState> build() async {
    return const MusicPlatformLibraryState();
  }
}

class _MemoryMusicPlaybackQueueStore implements MusicPlaybackQueueStore {
  final Map<String, MusicPlaybackQueueSnapshot> snapshots =
      <String, MusicPlaybackQueueSnapshot>{};

  @override
  Future<MusicPlaybackQueueSnapshot?> load(String ownerId) async {
    return snapshots[ownerId];
  }

  @override
  Future<void> save(String ownerId, MusicPlaybackQueueSnapshot snapshot) async {
    snapshots[ownerId] = snapshot;
  }
}

class _FakeMusicApi implements MusicApi {
  final track = const MusicTrack(
    id: 'track-1',
    fileNodeId: 'file-1',
    title: 'Night Drive',
    artistName: 'Omni Band',
    albumTitle: 'Unknown Album',
    format: 'flac',
    favorite: false,
  );
  final secondTrack = const MusicTrack(
    id: 'track-2',
    fileNodeId: 'file-2',
    title: 'Morning Ride',
    artistName: 'Omni Band',
    albumTitle: 'Unknown Album',
    format: 'mp3',
    favorite: false,
  );
  final libraryTracks = <MusicTrack>[];
  final playbackPlanTrackIds = <String>[];
  final onlinePlaybackRequests = <String>[];
  final lyricsRequests = <String>[];
  final onlineLyrics = <String, String>{};
  final recordedHistoryKeys = <String>[];
  MusicPlaybackQueueSnapshot restoredPlaybackQueue =
      const MusicPlaybackQueueSnapshot();
  final savedPlaybackQueues = <MusicPlaybackQueueSnapshot>[];
  int playbackQueueLoadAttempts = 0;
  int queueSaveAttempts = 0;
  int queueSaveFailuresRemaining = 0;
  List<MusicRecentEntry> recentEntries = <MusicRecentEntry>[];
  Object? onlinePlaybackError;
  final playlist = const MusicPlaylist(
    id: 'playlist-1',
    name: 'Road Trip',
    playlistType: 'CUSTOM',
    trackCount: 0,
  );
  final addedPlaylistItems = <String, List<String>>{};
  final removedPlaylistItems = <String, List<String>>{};
  final loadedPlaylistIds = <String>[];
  final deletedTrackIds = <String>[];
  final deletedPlaylistIds = <String>[];
  final uploadedCoverNames = <String>[];
  String? createdPlaylistCoverFileId;
  String? updatedPlaylistCoverFileId;
  String? updatedTrackId;
  String? updatedTrackTitle;
  String? updatedTrackArtistName;
  String? updatedTrackAlbumTitle;
  String? updatedTrackGenre;
  String? updatedTrackLyricsRaw;
  String? updatedTrackCoverFileId;
  final scrapeCandidateTrackIds = <String>[];
  final appliedScrapeTrackIds = <String>[];
  final appliedLyricsTrackIds = <String>[];
  final appliedLyricsTexts = <String>[];
  final scrapeLibraryForceFlags = <bool>[];
  List<MusicPlatformStatus> platformStatuses = const <MusicPlatformStatus>[];
  final Set<String> failingPlaylistPlatforms = <String>{};
  final List<String> platformPlaylistTrackRequests = <String>[];
  final Map<String, Completer<List<OnlineTrack>>> pendingSearches =
      <String, Completer<List<OnlineTrack>>>{};

  _FakeMusicApi() {
    libraryTracks.addAll([track, secondTrack]);
  }

  @override
  Future<MusicDashboard> dashboard() async => MusicDashboard.empty();

  final tracksPageRequests = <int>[];

  @override
  Future<MusicPagedResult<MusicTrack>> tracks({
    int page = 0,
    int size = 100,
    String sort = 'title,asc',
  }) async {
    tracksPageRequests.add(page);
    final all = libraryTracks;
    final start = page * size;
    final items =
        start >= all.length
            ? const <MusicTrack>[]
            : all.sublist(start, (start + size).clamp(0, all.length));
    return MusicPagedResult<MusicTrack>(
      items: items,
      page: page,
      size: size,
      totalElements: all.length,
    );
  }

  @override
  Future<MusicPagedResult<MusicAlbum>> albums({
    int page = 0,
    int size = 100,
    String sort = 'updatedAt,desc',
  }) async => const MusicPagedResult<MusicAlbum>(
    items: <MusicAlbum>[],
    page: 0,
    size: 0,
    totalElements: 0,
  );

  @override
  Future<MusicPagedResult<MusicArtist>> artists({
    int page = 0,
    int size = 100,
    String sort = 'name,asc',
  }) async => const MusicPagedResult<MusicArtist>(
    items: <MusicArtist>[],
    page: 0,
    size: 0,
    totalElements: 0,
  );

  @override
  Future<List<MusicPlaylist>> playlists() async => [playlist];

  @override
  Future<List<MusicPlatformStatus>> musicPlatforms() async => platformStatuses;

  @override
  Future<List<OnlinePlaylist>> platformPlaylists(String platform) async {
    if (failingPlaylistPlatforms.contains(platform)) {
      throw StateError('$platform playlist failure');
    }
    if (platform == 'qq') {
      return const <OnlinePlaylist>[
        OnlinePlaylist(
          platform: 'qq',
          playlistId: 'qq-list-1',
          name: 'QQ Collection',
        ),
      ];
    }
    return const <OnlinePlaylist>[];
  }

  @override
  Future<List<OnlineTrack>> platformPlaylistTracks(
    String platform,
    String playlistId,
  ) async {
    platformPlaylistTrackRequests.add('$platform:$playlistId');
    return <OnlineTrack>[
      OnlineTrack(
        platform: platform,
        songId: 'playlist-song-1',
        title: 'Playlist Song',
        artistName: 'Playlist Artist',
        coverUrl: 'https://example.com/$platform-cover.jpg',
      ),
    ];
  }

  @override
  Future<List<OnlineTrack>> platformLikedTracks(String platform) async {
    if (platform == 'netease') {
      return const <OnlineTrack>[
        OnlineTrack(
          platform: 'netease',
          songId: 'liked-1',
          title: 'Liked Song',
          artistName: 'Cloud Artist',
        ),
      ];
    }
    return const <OnlineTrack>[];
  }

  @override
  Future<DailyRecommendedTracks> platformDailyRecommendedTracks(
    String platform,
  ) async {
    return DailyRecommendedTracks(
      platform: platform,
      recommendationDate: DateTime(2026, 8, 11),
      tracks: const <OnlineTrack>[],
    );
  }

  @override
  Future<MusicPlatformLyrics?> platformTrackLyrics(
    String platform,
    String songId,
  ) async {
    lyricsRequests.add('$platform:$songId');
    final raw = onlineLyrics[songId];
    return raw == null ? null : MusicPlatformLyrics(lyrics: raw);
  }

  @override
  Future<MusicPlaybackPlan> playbackPlan(String trackId) async {
    playbackPlanTrackIds.add(trackId);
    return MusicPlaybackPlan(
      trackId: trackId,
      url: 'http://localhost/$trackId.flac',
      durationSeconds: 245,
      format: 'flac',
    );
  }

  @override
  Future<void> recordPlayHistory(String trackId, {int playDuration = 0}) async {
    recordedHistoryKeys.add('local:$trackId');
  }

  @override
  Future<void> recordPlayableHistory({
    required String playableKey,
    required String title,
    required String artistName,
    required String albumTitle,
    required String coverUrl,
    required int? durationSeconds,
    String? mediaMid,
    int playDuration = 0,
  }) async {
    recordedHistoryKeys.add(playableKey);
  }

  @override
  Future<MusicPlaybackQueueSnapshot> playbackQueue() async {
    playbackQueueLoadAttempts++;
    return restoredPlaybackQueue;
  }

  @override
  Future<void> savePlaybackQueue(MusicPlaybackQueueSnapshot snapshot) async {
    queueSaveAttempts++;
    if (queueSaveFailuresRemaining > 0) {
      queueSaveFailuresRemaining--;
      throw const AppException(
        code: 'REQUEST_TIMEOUT',
        message: 'Queue save timed out',
      );
    }
    savedPlaybackQueues.add(snapshot);
  }

  @override
  Future<MusicTrack?> lastPlayed() async => null;

  @override
  Future<MusicPlaylist> addPlaylistItems(
    String playlistId,
    List<String> trackIds,
  ) async {
    addedPlaylistItems[playlistId] = trackIds;
    return MusicPlaylist(
      id: playlistId,
      name: playlist.name,
      playlistType: playlist.playlistType,
      trackCount: trackIds.length,
    );
  }

  @override
  Future<MusicTrack> applyScrapeCandidate(
    String trackId,
    MusicScrapeCandidate candidate,
  ) async {
    appliedScrapeTrackIds.add(trackId);
    return libraryTracks.firstWhere((track) => track.id == trackId);
  }

  @override
  ApiClient get apiClient => ApiClient(
    const AppEnvironment(
      apiBaseUrl: 'http://localhost:8080/api/v1',
      wsBaseUrl: 'ws://localhost:8080/ws',
    ),
  );

  @override
  Future<MusicScanJob> createScanJob() => throw UnimplementedError();

  @override
  Future<MusicPlaylist> createPlaylist({
    required String name,
    String? description,
    String? coverFileId,
  }) async {
    createdPlaylistCoverFileId = coverFileId;
    return MusicPlaylist(
      id: 'playlist-created',
      name: name,
      description: description,
      playlistType: 'CUSTOM',
      coverFileId: coverFileId,
      coverUrl: 'http://localhost/$coverFileId.jpg',
      trackCount: 0,
    );
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    deletedPlaylistIds.add(playlistId);
  }

  @override
  Future<TaskSubmission> deleteTrack(
    String trackId, {
    bool cascade = false,
  }) async {
    deletedTrackIds.add(trackId);
    libraryTracks.removeWhere((track) => track.id == trackId);
    return const TaskSubmission(taskId: 'task-delete-track', status: 'QUEUED');
  }

  @override
  Future<void> favorite(String trackId) => throw UnimplementedError();

  @override
  Future<List<MusicTrack>> favorites() => throw UnimplementedError();

  @override
  Future<List<MusicTrack>> recent() => throw UnimplementedError();

  @override
  Future<List<MusicRecentEntry>> recentItems() async =>
      List<MusicRecentEntry>.of(recentEntries);

  @override
  Future<MusicPagedResult<MusicPlayHistoryEntry>> playHistory({
    int page = 0,
    int size = 50,
  }) async => const MusicPagedResult<MusicPlayHistoryEntry>(
    items: <MusicPlayHistoryEntry>[],
  );

  @override
  Future<List<MusicTrack>> playlistTracks(String playlistId) =>
      Future.value([track, secondTrack]).then((tracks) {
        loadedPlaylistIds.add(playlistId);
        return tracks;
      });

  @override
  Future<MusicPlaylist> removePlaylistItems(
    String playlistId,
    List<String> trackIds,
  ) async {
    removedPlaylistItems[playlistId] = trackIds;
    return MusicPlaylist(
      id: playlistId,
      name: playlist.name,
      playlistType: playlist.playlistType,
      trackCount: 1,
      coverUrl: 'http://localhost/track-2.jpg',
    );
  }

  @override
  Future<void> removeFavorite(String trackId) => throw UnimplementedError();

  @override
  Future<MusicScanJob> scanJobStatus(String jobId) =>
      throw UnimplementedError();

  @override
  Future<List<MusicScrapeCandidate>> scrapeCandidates(String trackId) async {
    scrapeCandidateTrackIds.add(trackId);
    return const [];
  }

  @override
  Future<MusicScanJob> scrapeLibrary({bool force = false}) async {
    scrapeLibraryForceFlags.add(force);
    return const MusicScanJob(
      id: 'scrape-job',
      status: 'COMPLETED',
      progress: 100,
      scannedFiles: 2,
    );
  }

  @override
  Future<MusicSearchResult> search(String keyword) =>
      throw UnimplementedError();

  @override
  Future<void> updateTrack({
    required String trackId,
    String? title,
    String? artistName,
    String? albumTitle,
    String? genre,
    String? lyricsRaw,
    String? coverFileId,
  }) async {
    updatedTrackId = trackId;
    updatedTrackTitle = title;
    updatedTrackArtistName = artistName;
    updatedTrackAlbumTitle = albumTitle;
    updatedTrackGenre = genre;
    updatedTrackLyricsRaw = lyricsRaw;
    updatedTrackCoverFileId = coverFileId;
  }

  @override
  Future<String> uploadCover({
    required List<int> bytes,
    required String fileName,
  }) async {
    uploadedCoverNames.add(fileName);
    return 'fake-cover-id';
  }

  @override
  Future<MusicPlaylist> updatePlaylist({
    required String playlistId,
    required String name,
    String? description,
    String? coverFileId,
  }) async {
    updatedPlaylistCoverFileId = coverFileId;
    return MusicPlaylist(
      id: playlistId,
      name: name,
      description: description,
      playlistType: 'CUSTOM',
      coverFileId: coverFileId,
      coverUrl: 'http://localhost/$coverFileId.jpg',
      trackCount: 0,
    );
  }

  @override
  Map<String, dynamic> parseData(Map<String, dynamic>? body) =>
      throw UnimplementedError();

  @override
  Map<String, dynamic> parseEnvelope(Map<String, dynamic>? body) =>
      throw UnimplementedError();

  @override
  Future<MusicPlaybackPosition> lastPosition() async =>
      const MusicPlaybackPosition(trackId: '', positionSeconds: 0);

  @override
  Future<void> savePosition({
    required String trackId,
    required int positionSeconds,
  }) async {}

  @override
  Future<MusicPlaybackProgress?> playbackProgress(String playableKey) async =>
      null;

  @override
  Future<MusicPlaybackProgress> savePlaybackProgress(
    MusicPlaybackProgress progress,
  ) async => progress;

  @override
  String streamUrl(String trackId) => 'http://localhost/$trackId.flac';

  @override
  Future<List<OnlineTrack>> onlineSearch(
    String query, {
    int limit = 20,
    String? platform,
    CancelToken? cancelToken,
  }) async {
    final completer = Completer<List<OnlineTrack>>();
    pendingSearches[query] = completer;
    return completer.future;
  }

  void completeSearch(String query) {
    pendingSearches.remove(query)?.complete(<OnlineTrack>[
      OnlineTrack(
        platform: 'netease',
        songId: '$query-song',
        title: '$query result',
        artistName: 'Search Artist',
      ),
    ]);
  }

  @override
  Future<MusicPlaybackPlan> onlinePlaybackPlan(
    String platform,
    String songId, {
    String? mediaMid,
    String quality = 'exhigh',
  }) async {
    onlinePlaybackRequests.add('$platform:$songId:${mediaMid ?? ''}');
    final error = onlinePlaybackError;
    if (error != null) {
      throw error;
    }
    return const MusicPlaybackPlan(
      trackId: 'online-track',
      url: 'http://localhost/online-track.mp3',
      format: 'mp3',
    );
  }

  @override
  Future<QrLoginSession> createNeteaseQrLogin() async {
    return QrLoginSession.fromJson(const <String, dynamic>{});
  }

  @override
  Future<QrLoginStatus> checkNeteaseQrLogin(String key) async {
    return QrLoginStatus.fromJson(const <String, dynamic>{});
  }

  @override
  Future<PlatformUserInfo> applyQqCookie(String cookie) async {
    return PlatformUserInfo.fromJson(const <String, dynamic>{});
  }

  @override
  Future<void> platformLogout(String platform) async {}

  @override
  Future<PlatformUserInfo?> platformInfo(String platform) async => null;

  @override
  Future<MusicLyricsResult?> searchLyrics(String trackId) async =>
      const MusicLyricsResult(
        syncedLyrics: '[00:01.00] stub',
        trackName: 'Night Drive',
        artistName: 'Omni Band',
      );

  @override
  Future<MusicTrack> applyLyrics(String trackId, String lyrics) async {
    appliedLyricsTrackIds.add(trackId);
    appliedLyricsTexts.add(lyrics);
    return libraryTracks.firstWhere((track) => track.id == trackId);
  }
}

class _DelayedMusicApi extends _FakeMusicApi {
  Completer<void>? _firstTrackGate;
  bool delayFirstTrack = false;

  void releaseFirstTrack() {
    _firstTrackGate?.complete();
  }

  @override
  Future<MusicPlaybackPlan> playbackPlan(String trackId) async {
    if (delayFirstTrack && trackId == track.id) {
      _firstTrackGate = Completer<void>();
      await _firstTrackGate!.future;
    }
    return super.playbackPlan(trackId);
  }
}
