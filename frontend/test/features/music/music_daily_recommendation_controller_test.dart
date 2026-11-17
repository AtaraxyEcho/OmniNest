import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_daily_recommendation_controller.dart';
import 'package:omninest/features/music/application/music_platform_library_controller.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/domain/music_models.dart';

void main() {
  test(
    'loads daily tracks for a connected supported NetEase account',
    () async {
      final adapter = _CountingHttpClientAdapter();
      final container = ProviderContainer.test(
        overrides: [
          musicApiProvider.overrideWithValue(MusicApi(_apiClient(adapter))),
          musicPlatformLibraryProvider.overrideWith(
            () => _FakePlatformLibraryController(_connectedState),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(musicPlatformLibraryProvider.future);
      final recommendation = await container.read(
        musicDailyRecommendationProvider.future,
      );

      expect(recommendation?.tracks.single.songId, 'song-1');
      expect(adapter.requestCount, 1);
      expect(
        adapter.lastPath,
        '/music/platforms/netease/recommendations/daily-tracks',
      );
    },
  );

  test(
    'does not request daily tracks before the NetEase account is connected',
    () async {
      final adapter = _CountingHttpClientAdapter();
      final container = ProviderContainer.test(
        overrides: [
          musicApiProvider.overrideWithValue(MusicApi(_apiClient(adapter))),
          musicPlatformLibraryProvider.overrideWith(
            () => _FakePlatformLibraryController(_disconnectedState),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(musicPlatformLibraryProvider.future);
      final recommendation = await container.read(
        musicDailyRecommendationProvider.future,
      );

      expect(recommendation, isNull);
      expect(adapter.requestCount, 0);
    },
  );
}

const MusicPlatformLibraryState _connectedState = MusicPlatformLibraryState(
  statuses: [
    MusicPlatformStatus(
      platform: 'netease',
      displayName: 'NetEase Cloud Music',
      enabled: true,
      connected: true,
      capabilities: MusicPlatformCapabilities(dailyRecommendations: true),
    ),
  ],
);

const MusicPlatformLibraryState _disconnectedState = MusicPlatformLibraryState(
  statuses: [
    MusicPlatformStatus(
      platform: 'netease',
      displayName: 'NetEase Cloud Music',
      enabled: true,
      connected: false,
      capabilities: MusicPlatformCapabilities(dailyRecommendations: true),
    ),
  ],
);

class _FakePlatformLibraryController extends MusicPlatformLibraryController {
  _FakePlatformLibraryController(this.initialState);

  final MusicPlatformLibraryState initialState;

  @override
  Future<MusicPlatformLibraryState> build() async => initialState;
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

class _CountingHttpClientAdapter implements HttpClientAdapter {
  int requestCount = 0;
  String? lastPath;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    lastPath = options.path;
    return ResponseBody.fromString(
      jsonEncode({
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
            },
          ],
        },
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
