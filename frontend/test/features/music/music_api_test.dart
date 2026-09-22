import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';

void main() {
  test('playback plan maps backend response', () {
    final plan = MusicApi.parsePlaybackPlan({
      'trackId': 'track-1',
      'url': 'http://localhost/audio.flac',
      'expiresAt': '2026-05-21T11:00:00Z',
      'durationSeconds': 245,
      'format': 'flac',
    });

    expect(plan.trackId, 'track-1');
    expect(plan.url, 'http://localhost/audio.flac');
    expect(plan.durationSeconds, 245);
    expect(plan.format, 'flac');
  });

  test('playback plan endpoint uses track id path', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': {
          'trackId': 'track-1',
          'url': 'http://localhost/audio.flac',
          'expiresAt': '2026-05-21T11:00:00Z',
          'durationSeconds': 245,
          'format': 'flac',
        },
      },
    );
    final api = MusicApi(_apiClient(adapter));

    await api.playbackPlan('track-1');

    expect(adapter.lastMethod, 'GET');
    expect(adapter.lastPath, '/music/tracks/track-1/playback-plan');
  });

  test(
    'playback plan resolves api relative stream url to absolute url',
    () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'trackId': 'track-1',
            'url': '/api/v1/music/playback/sessions/session-1/stream?token=abc',
            'expiresAt': '2026-05-21T11:00:00Z',
            'durationSeconds': 245,
            'format': 'flac',
          },
        },
      );
      final api = MusicApi(_apiClient(adapter));

      final plan = await api.playbackPlan('track-1');

      expect(
        plan.url,
        'http://localhost:8080/api/v1/music/playback/sessions/session-1/stream?token=abc',
      );
    },
  );

  test('playback plan adds api prefix for legacy relative stream url', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': {
          'trackId': 'track-1',
          'url': '/music/playback/sessions/session-1/stream?token=abc',
          'expiresAt': '2026-05-21T11:00:00Z',
          'durationSeconds': 245,
          'format': 'flac',
        },
      },
    );
    final api = MusicApi(_apiClient(adapter));

    final plan = await api.playbackPlan('track-1');

    expect(
      plan.url,
      'http://localhost:8080/api/v1/music/playback/sessions/session-1/stream?token=abc',
    );
  });

  test('music progress endpoints use playable key contract', () async {
    final loadAdapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': {
          'playableKey': 'online:netease:song-1',
          'positionSeconds': 75,
          'durationSeconds': 180,
          'completed': false,
          'updatedAt': '2026-07-10T04:00:00Z',
          'version': 2,
        },
      },
    );
    final loadApi = MusicApi(_apiClient(loadAdapter));

    final loaded = await loadApi.playbackProgress('online:netease:song-1');

    expect(loadAdapter.lastMethod, 'GET');
    expect(loadAdapter.lastPath, '/music/progress');
    expect(loadAdapter.lastQueryParameters, {
      'playableKey': 'online:netease:song-1',
    });
    expect(loaded?.positionSeconds, 75);
    expect(loaded?.version, 2);

    final saveAdapter = _CapturingHttpClientAdapter(body: loadAdapter.body);
    final saveApi = MusicApi(_apiClient(saveAdapter));
    SharedPreferences.setMockInitialValues({
      'playback_device_id': 'test-device',
    });
    final progress = MusicPlaybackProgress(
      playableKey: 'online:netease:song-1',
      positionSeconds: 90,
      durationSeconds: 180,
      completed: false,
      updatedAt: DateTime(2026, 7, 10),
    );

    await saveApi.savePlaybackProgress(progress);

    expect(saveAdapter.lastMethod, 'PUT');
    expect(saveAdapter.lastPath, '/music/progress');
    expect(saveAdapter.lastData, {
      ...progress.toSaveJson(),
      'deviceId': 'test-device',
    });
  });

  test('missing music progress maps to null', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {'code': 200, 'message': 'success', 'data': null},
    );
    final api = MusicApi(_apiClient(adapter));

    expect(await api.playbackProgress('local:track-1'), isNull);
  });

  test('online playback plan uses signed playback plan endpoint', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': {
          'trackId': null,
          'url': '/api/v1/music/playback/sessions/session-2/stream?token=xyz',
          'expiresAt': '2026-05-21T11:00:00Z',
          'durationSeconds': null,
          'format': 'mp3',
        },
      },
    );
    final api = MusicApi(_apiClient(adapter));

    final plan = await api.onlinePlaybackPlan('netease', 'song-1');

    expect(adapter.lastMethod, 'GET');
    expect(adapter.lastPath, '/music/online/playback-plan');
    expect(adapter.lastQueryParameters, {
      'platform': 'netease',
      'songId': 'song-1',
      'quality': 'exhigh',
    });
    expect(
      plan.url,
      'http://localhost:8080/api/v1/music/playback/sessions/session-2/stream?token=xyz',
    );
    expect(plan.format, 'mp3');
  });

  test('platform status maps connection and capability metadata', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': [
          {
            'platform': 'netease',
            'displayName': '网易云音乐',
            'enabled': true,
            'connected': true,
            'userInfo': {
              'platform': 'netease',
              'userId': 'user-1',
              'nickname': 'Music User',
              'vip': false,
            },
            'capabilities': {
              'search': true,
              'playlists': true,
              'likedTracks': true,
              'lyrics': true,
              'dailyRecommendations': true,
              'qualityLevels': ['standard', 'high'],
            },
            'lastVerifiedAt': '2026-07-10T04:00:00Z',
            'recoverableErrors': <String>[],
          },
        ],
      },
    );
    final api = MusicApi(_apiClient(adapter));

    final platforms = await api.musicPlatforms();

    expect(adapter.lastMethod, 'GET');
    expect(adapter.lastPath, '/music/platforms');
    expect(platforms.single.connected, isTrue);
    expect(platforms.single.userInfo?.nickname, 'Music User');
    expect(platforms.single.capabilities.likedTracks, isTrue);
    expect(platforms.single.capabilities.dailyRecommendations, isTrue);
    expect(platforms.single.capabilities.qualityLevels, ['standard', 'high']);
  });

  test('platform playlist endpoints use canonical resource paths', () async {
    final playlistAdapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': [
          {
            'platform': 'netease',
            'playlistId': 'playlist-1',
            'name': 'Daily Mix',
            'trackCount': 12,
            'subscribed': true,
          },
        ],
      },
    );
    final playlistApi = MusicApi(_apiClient(playlistAdapter));

    final playlists = await playlistApi.platformPlaylists('netease');

    expect(playlistAdapter.lastMethod, 'GET');
    expect(playlistAdapter.lastPath, '/music/platforms/netease/playlists');
    expect(playlists.single.name, 'Daily Mix');

    final trackAdapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': [
          {
            'platform': 'netease',
            'songId': 'song-1',
            'title': 'Night Drive',
            'artistName': 'Omni Band',
          },
        ],
      },
    );
    final trackApi = MusicApi(_apiClient(trackAdapter));

    final tracks = await trackApi.platformPlaylistTracks(
      'netease',
      'playlist-1',
    );

    expect(trackAdapter.lastMethod, 'GET');
    expect(
      trackAdapter.lastPath,
      '/music/platforms/netease/playlists/playlist-1/tracks',
    );
    expect(tracks.single.songId, 'song-1');
  });

  test('liked tracks endpoint is scoped to the selected platform', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': <Map<String, dynamic>>[],
      },
    );
    final api = MusicApi(_apiClient(adapter));

    await api.platformLikedTracks('netease');

    expect(adapter.lastMethod, 'GET');
    expect(adapter.lastPath, '/music/platforms/netease/liked-tracks');
  });

  test(
    'platform lyrics prefer synchronized lyrics and pass word payload through',
    () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {
            'plainLyrics': 'Cloud',
            'syncedLyrics': '[00:01.00]Cloud',
            'wordLyrics': '[1000,2000](1000,500,0)Cloud',
          },
        },
      );
      final api = MusicApi(_apiClient(adapter));

      final lyrics = await api.platformTrackLyrics('netease', 'song-1');

      expect(adapter.lastMethod, 'GET');
      expect(adapter.lastPath, '/music/platforms/netease/tracks/song-1/lyrics');
      expect(lyrics?.lyrics, '[00:01.00]Cloud');
      expect(lyrics?.words, '[1000,2000](1000,500,0)Cloud');

      // 平台不提供逐字载荷时为 null，调用方退回行级显示。
      final plainAdapter = _CapturingHttpClientAdapter(
        body: {
          'code': 200,
          'message': 'success',
          'data': {'syncedLyrics': '[00:01.00]Cloud'},
        },
      );
      final plainApi = MusicApi(_apiClient(plainAdapter));
      final plainLyrics = await plainApi.platformTrackLyrics(
        'netease',
        'song-1',
      );
      expect(plainLyrics?.words, isNull);
    },
  );

  test('QR login and disconnect use canonical platform paths', () async {
    final createAdapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': {'loginKey': 'session-1', 'qrUrl': 'https://example.test/qr'},
      },
    );
    final createApi = MusicApi(_apiClient(createAdapter));

    final session = await createApi.createNeteaseQrLogin();

    expect(session.loginKey, 'session-1');
    expect(createAdapter.lastMethod, 'POST');
    expect(createAdapter.lastPath, '/music/platforms/netease/login-sessions');

    final checkAdapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': {'status': 'waiting'},
      },
    );
    final checkApi = MusicApi(_apiClient(checkAdapter));

    await checkApi.checkNeteaseQrLogin('session-1');

    expect(checkAdapter.lastMethod, 'GET');
    expect(
      checkAdapter.lastPath,
      '/music/platforms/netease/login-sessions/session-1',
    );
    expect(checkAdapter.lastQueryParameters, isEmpty);

    final disconnectAdapter = _CapturingHttpClientAdapter();
    final disconnectApi = MusicApi(_apiClient(disconnectAdapter));

    await disconnectApi.platformLogout('netease');

    expect(disconnectAdapter.lastMethod, 'DELETE');
    expect(disconnectAdapter.lastPath, '/music/platforms/netease/connection');
  });

  test('online track reads media id from provider metadata', () {
    final track = OnlineTrack.fromJson({
      'platform': 'netease',
      'songId': 'song-mid',
      'title': 'Night Drive',
      'artistName': 'Omni Band',
    });

    expect(track.songId, 'song-mid');
  });

  test('QR login status does not retain a response cookie', () {
    final status = QrLoginStatus.fromJson({
      'status': 'confirmed',
      'cookie': 'MUSIC_U=secret',
      'userInfo': {
        'platform': 'netease',
        'userId': 'user-1',
        'nickname': 'Music User',
        'vip': false,
      },
    });

    expect(status.status, 'confirmed');
    expect(status.userInfo?.userId, 'user-1');
  });

  test('scan job status endpoint uses admin status path', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': {
          'id': 'job-1',
          'status': 'COMPLETED',
          'progress': 100,
          'scannedFiles': 3,
        },
      },
    );
    final api = MusicApi(_apiClient(adapter));

    await api.scanJobStatus('job-1');

    expect(adapter.lastMethod, 'GET');
    expect(adapter.lastPath, '/admin/music/scan/job-1/status');
  });

  test('create playlist posts metadata and custom cover id', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': {
          'id': 'playlist-1',
          'name': 'Road Trip',
          'playlistType': 'CUSTOM',
          'trackCount': 0,
        },
      },
    );
    final api = MusicApi(_apiClient(adapter));

    await api.createPlaylist(
      name: 'Road Trip',
      description: 'Night songs',
      coverFileId: 'cover-1',
    );

    expect(adapter.lastMethod, 'POST');
    expect(adapter.lastPath, '/music/playlists');
    expect(adapter.lastData, {
      'name': 'Road Trip',
      'description': 'Night songs',
      'coverFileId': 'cover-1',
    });
  });

  test('update playlist sends custom cover id', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': {
          'id': 'playlist-1',
          'name': 'Road Trip 2',
          'playlistType': 'CUSTOM',
          'coverFileId': 'cover-2',
          'trackCount': 0,
        },
      },
    );
    final api = MusicApi(_apiClient(adapter));

    final playlist = await api.updatePlaylist(
      playlistId: 'playlist-1',
      name: 'Road Trip 2',
      description: 'Updated',
      coverFileId: 'cover-2',
    );

    expect(adapter.lastMethod, 'PUT');
    expect(adapter.lastPath, '/music/playlists/playlist-1');
    expect(adapter.lastData, {
      'name': 'Road Trip 2',
      'description': 'Updated',
      'coverFileId': 'cover-2',
    });
    expect(playlist.coverFileId, 'cover-2');
  });

  test('upload cover sends multipart file to music cover endpoint', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': {'fileId': 'cover-3'},
      },
    );
    final api = MusicApi(_apiClient(adapter));

    final fileId = await api.uploadCover(
      bytes: const [0xFF, 0xD8, 0xFF],
      fileName: 'cover.jpg',
    );

    expect(adapter.lastMethod, 'POST');
    expect(adapter.lastPath, '/music/covers');
    expect(adapter.lastData, isA<FormData>());
    expect(fileId, 'cover-3');
  });

  test('add playlist items posts track ids', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': {
          'id': 'playlist-1',
          'name': 'Road Trip',
          'playlistType': 'CUSTOM',
          'trackCount': 1,
        },
      },
    );
    final api = MusicApi(_apiClient(adapter));

    await api.addPlaylistItems('playlist-1', ['track-1']);

    expect(adapter.lastMethod, 'POST');
    expect(adapter.lastPath, '/music/playlists/playlist-1/items');
    expect(adapter.lastData, {
      'trackIds': ['track-1'],
    });
  });

  test('remove playlist items returns refreshed playlist summary', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': {
          'id': 'playlist-1',
          'name': 'Road Trip',
          'playlistType': 'CUSTOM',
          'coverUrl': 'https://example.test/second.jpg',
          'trackCount': 1,
        },
      },
    );
    final api = MusicApi(_apiClient(adapter));

    final playlist = await api.removePlaylistItems('playlist-1', ['track-1']);

    expect(adapter.lastMethod, 'DELETE');
    expect(adapter.lastPath, '/music/playlists/playlist-1/items');
    expect(adapter.lastData, {
      'trackIds': ['track-1'],
    });
    expect(playlist.coverUrl, 'https://example.test/second.jpg');
  });

  test('delete track sends delete request to track endpoint', () async {
    final adapter = _CapturingHttpClientAdapter();
    final api = MusicApi(_apiClient(adapter));

    await api.deleteTrack('track-1');

    expect(adapter.lastMethod, 'DELETE');
    expect(adapter.lastPath, '/music/tracks/track-1');
  });

  test('scrape candidates endpoint maps MusicBrainz results', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': [
          {
            'provider': 'MusicBrainz',
            'externalId': 'rec-1',
            'title': 'Night Drive',
            'artistName': 'Omni Band',
            'albumTitle': 'City Lights',
            'score': 92,
          },
        ],
      },
    );
    final api = MusicApi(_apiClient(adapter));

    final candidates = await api.scrapeCandidates('track-1');

    expect(adapter.lastMethod, 'GET');
    expect(adapter.lastPath, '/admin/music/tracks/track-1/scrape-candidates');
    expect(candidates.single.externalId, 'rec-1');
    expect(candidates.single.score, 92);
  });

  test('apply scrape candidate posts selected fields', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': {
          'id': 'track-1',
          'fileNodeId': 'file-1',
          'title': 'Night Drive',
          'artistName': 'Omni Band',
          'albumTitle': 'City Lights',
          'format': 'flac',
          'favorite': false,
        },
      },
    );
    final api = MusicApi(_apiClient(adapter));

    await api.applyScrapeCandidate(
      'track-1',
      MusicScrapeCandidate(
        provider: 'MusicBrainz',
        externalId: 'rec-1',
        title: 'Night Drive',
        artistName: 'Omni Band',
        albumTitle: 'City Lights',
        score: 92,
      ),
    );

    expect(adapter.lastMethod, 'POST');
    expect(adapter.lastPath, '/admin/music/tracks/track-1/scrape/apply');
    expect((adapter.lastData as Map<String, dynamic>)['externalId'], 'rec-1');
  });

  test('scrape library posts force flag', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': {
          'id': 'job-1',
          'status': 'COMPLETED',
          'progress': 100,
          'scannedFiles': 2,
        },
      },
    );
    final api = MusicApi(_apiClient(adapter));

    await api.scrapeLibrary(force: true);

    expect(adapter.lastMethod, 'POST');
    expect(adapter.lastPath, '/admin/music/scrape');
    expect(adapter.lastData, {'force': true});
  });

  test('unified recent items map online track snapshots', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': [
          {
            'playableKey': 'online:netease:song-1',
            'onlineTrack': {
              'platform': 'netease',
              'songId': 'song-1',
              'title': 'Cloud Song',
              'artistName': 'Cloud Artist',
              'coverUrl': 'https://example.com/cover.jpg',
            },
            'playedAt': '2026-07-12T01:00:00Z',
          },
        ],
      },
    );
    final api = MusicApi(_apiClient(adapter));

    final recent = await api.recentItems();

    expect(adapter.lastMethod, 'GET');
    expect(adapter.lastPath, '/music/recent-items');
    expect(recent.single.onlineTrack?.songId, 'song-1');
  });

  test('unified play history posts typed online snapshot', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {'code': 200, 'message': 'success', 'data': null},
    );
    final api = MusicApi(_apiClient(adapter));

    await api.recordPlayableHistory(
      playableKey: 'online:netease:song-2',
      title: 'Cloud Song',
      artistName: 'Cloud Artist',
      albumTitle: 'Cloud Album',
      coverUrl: 'https://example.com/cover.jpg',
      durationSeconds: 180,
    );

    expect(adapter.lastMethod, 'POST');
    expect(adapter.lastPath, '/music/play-history');
    expect(
      (adapter.lastData as Map<String, dynamic>)['playableKey'],
      'online:netease:song-2',
    );
  });

  test('daily recommendation uses platform endpoint and maps tracks', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': {
          'platform': 'netease',
          'recommendationDate': '2026-08-11',
          'tracks': [
            {
              'platform': 'netease',
              'songId': 'song-1',
              'title': 'Daily Song',
              'artistName': 'Daily Artist',
              'coverUrl': 'https://example.com/daily.jpg',
            },
          ],
        },
      },
    );
    final api = MusicApi(_apiClient(adapter));

    final recommendation = await api.platformDailyRecommendedTracks('netease');

    expect(adapter.lastMethod, 'GET');
    expect(
      adapter.lastPath,
      '/music/platforms/netease/recommendations/daily-tracks',
    );
    expect(recommendation.platform, 'netease');
    expect(recommendation.recommendationDate, DateTime(2026, 8, 11));
    expect(recommendation.tracks.single.songId, 'song-1');
    expect(recommendation.coverUrl, 'https://example.com/daily.jpg');
  });

  test('playback queue restores typed online descriptors', () async {
    final adapter = _CapturingHttpClientAdapter(
      body: {
        'code': 200,
        'message': 'success',
        'data': {
          'items': [
            {
              'playableKey': 'online:netease:188888',
              'title': 'Cloud Song',
              'artistName': 'Cloud Artist',
              'albumTitle': 'Cloud Album',
              'durationSeconds': 180,
              'format': 'mp3',
            },
          ],
          'currentIndex': 0,
          'repeatMode': 'all',
          'shuffleEnabled': true,
          'updatedAt': '2026-07-13T12:30:00Z',
        },
      },
    );
    final api = MusicApi(_apiClient(adapter));

    final snapshot = await api.playbackQueue();

    expect(adapter.lastMethod, 'GET');
    expect(adapter.lastPath, '/music/playback-queue');
    expect(snapshot.currentItem?.playableKey, 'online:netease:188888');
    expect(snapshot.repeatMode, 'all');
    expect(snapshot.shuffleEnabled, isTrue);
    expect(snapshot.updatedAt, DateTime.utc(2026, 7, 13, 12, 30));
  });

  test(
    'playback queue saves stable descriptors without playback URL',
    () async {
      final adapter = _CapturingHttpClientAdapter(
        body: {'code': 200, 'message': 'success', 'data': {}},
      );
      final api = MusicApi(_apiClient(adapter));
      final item = MusicPlayableItem.online(
        const OnlineTrack(
          platform: 'netease',
          songId: 'song-2',
          title: 'Cloud Song',
          artistName: 'Cloud Artist',
        ),
      );

      await api.savePlaybackQueue(
        MusicPlaybackQueueSnapshot(items: [item], currentIndex: 0),
      );

      expect(adapter.lastMethod, 'PUT');
      expect(adapter.lastPath, '/music/playback-queue');
      final data = adapter.lastData as Map<String, dynamic>;
      final savedItem = (data['items'] as List).single as Map<String, dynamic>;
      expect(savedItem['playableKey'], 'online:netease:song-2');
      expect(savedItem.containsKey('url'), isFalse);
      expect(data.containsKey('updatedAt'), isFalse);
    },
  );
}

ApiClient _apiClient(HttpClientAdapter adapter) {
  return ApiClient(
    const AppEnvironment(
      apiBaseUrl: 'http://localhost:8080/api/v1',
      wsBaseUrl: 'ws://localhost:8080/ws',
    ),
    httpClientAdapter: adapter,
  );
}

class _CapturingHttpClientAdapter implements HttpClientAdapter {
  _CapturingHttpClientAdapter({
    this.body = const {'code': 200, 'message': 'success', 'data': {}},
  });

  final Map<String, dynamic> body;
  String? lastMethod;
  String? lastPath;
  Object? lastData;
  Map<String, dynamic>? lastQueryParameters;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastMethod = options.method;
    lastPath = options.path;
    lastData = options.data;
    lastQueryParameters = Map<String, dynamic>.from(options.queryParameters);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
