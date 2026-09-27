import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/video/domain/movie_library_models.dart';
import 'package:omninest/features/video/domain/series_play_target.dart';

MovieContinueWatching _continue({
  required String id,
  String? seriesId,
  int positionSeconds = 100,
}) {
  return MovieContinueWatching(
    id: id,
    title: 't',
    positionSeconds: positionSeconds,
    durationSeconds: 1000,
    progressPercent: 10,
    seriesId: seriesId,
  );
}

MovieWatchHistory _history({
  required String videoItemId,
  String? seriesId,
  bool completed = false,
  DateTime? playedAt,
}) {
  return MovieWatchHistory(
    id: 'h-$videoItemId',
    videoItemId: videoItemId,
    title: 't',
    positionSeconds: 10,
    durationSeconds: 100,
    completed: completed,
    seriesId: seriesId,
    playedAt: playedAt,
  );
}

MovieVideoItem _episode({
  required String id,
  int? seasonNumber,
  int? episodeNumber,
  String availabilityStatus = 'AVAILABLE',
}) {
  return MovieVideoItem(
    id: id,
    fileNodeId: 'f-$id',
    mediaType: 'EPISODE',
    title: id,
    metadataStatus: 'MATCHED',
    nfoStatus: 'NONE',
    updatedAt: DateTime(2026),
    metadata: const <String, dynamic>{},
    seasonNumber: seasonNumber,
    episodeNumber: episodeNumber,
    availabilityStatus: availabilityStatus,
  );
}

void main() {
  group('resolveSeriesPlayIntent', () {
    test('continue 列表命中系列时为 resume', () {
      final intent = resolveSeriesPlayIntent(
        seriesId: 's1',
        continueWatching: [
          _continue(id: 'ep2', seriesId: 's1'),
          _continue(id: 'other', seriesId: 's0'),
        ],
        history: const [],
      );
      expect(intent.kind, SeriesPlayIntentKind.resume);
      expect(intent.videoItemId, 'ep2');
    });

    test('历史未完成且不在 continue 时仍为 resume', () {
      final intent = resolveSeriesPlayIntent(
        seriesId: 's1',
        continueWatching: const [],
        history: [
          _history(videoItemId: 'ep3', seriesId: 's1', completed: false),
        ],
      );
      expect(intent.kind, SeriesPlayIntentKind.resume);
      expect(intent.videoItemId, 'ep3');
    });

    test('历史最近一条已完成时为 nextEpisode', () {
      final intent = resolveSeriesPlayIntent(
        seriesId: 's1',
        continueWatching: const [],
        history: [
          _history(
            videoItemId: 'ep1',
            seriesId: 's1',
            completed: true,
            playedAt: DateTime(2026, 1, 1),
          ),
          _history(
            videoItemId: 'ep0',
            seriesId: 's1',
            completed: true,
            playedAt: DateTime(2025, 1, 1),
          ),
        ],
      );
      expect(intent.kind, SeriesPlayIntentKind.nextEpisode);
      expect(intent.afterVideoItemId, 'ep1');
    });

    test('无记录时为 first', () {
      final intent = resolveSeriesPlayIntent(
        seriesId: 's1',
        continueWatching: [_continue(id: 'x', seriesId: 's2')],
        history: [_history(videoItemId: 'y', seriesId: 's2')],
      );
      expect(intent.kind, SeriesPlayIntentKind.first);
    });
  });

  group('pickSeriesPlayEpisodeId', () {
    final ordered = [
      _episode(id: 'e1', seasonNumber: 1, episodeNumber: 1),
      _episode(
        id: 'e2',
        seasonNumber: 1,
        episodeNumber: 2,
        availabilityStatus: 'MISSING',
      ),
      _episode(id: 'e3', seasonNumber: 1, episodeNumber: 3),
      _episode(id: 'e4', seasonNumber: 2, episodeNumber: 1),
    ];

    test('无锚点取第一个可播', () {
      expect(
        pickSeriesPlayEpisodeId(
          orderedEpisodes: ordered,
          afterVideoItemId: null,
        ),
        'e1',
      );
    });

    test('锚点后跳过不可播分集', () {
      expect(
        pickSeriesPlayEpisodeId(
          orderedEpisodes: ordered,
          afterVideoItemId: 'e1',
        ),
        'e3',
      );
    });

    test('锚点为最后一集时返回 null', () {
      expect(
        pickSeriesPlayEpisodeId(
          orderedEpisodes: ordered,
          afterVideoItemId: 'e4',
        ),
        isNull,
      );
    });

    test('锚点不存在时回落首集', () {
      expect(
        pickSeriesPlayEpisodeId(
          orderedEpisodes: ordered,
          afterVideoItemId: 'missing',
        ),
        'e1',
      );
    });
  });

  group('episodeUnavailableReason', () {
    test('AVAILABLE 为 none', () {
      expect(
        episodeUnavailableReason('AVAILABLE'),
        EpisodeUnavailableReason.none,
      );
    });

    test('MISSING 与 MISSING_PENDING 为文件缺失', () {
      expect(
        episodeUnavailableReason('MISSING'),
        EpisodeUnavailableReason.fileMissing,
      );
      expect(
        episodeUnavailableReason('MISSING_PENDING'),
        EpisodeUnavailableReason.fileMissing,
      );
    });

    test('CHANGED 为文件已变更', () {
      expect(
        episodeUnavailableReason('CHANGED'),
        EpisodeUnavailableReason.fileChanged,
      );
    });

    test('BLOCKED 与 UNAVAILABLE 为来源不可用', () {
      expect(
        episodeUnavailableReason('BLOCKED'),
        EpisodeUnavailableReason.sourceUnavailable,
      );
      expect(
        episodeUnavailableReason('UNAVAILABLE'),
        EpisodeUnavailableReason.sourceUnavailable,
      );
    });
  });

  test('sortEpisodesForPlay 按季号集号升序', () {
    final sorted = sortEpisodesForPlay([
      _episode(id: 'b', seasonNumber: 2, episodeNumber: 1),
      _episode(id: 'a2', seasonNumber: 1, episodeNumber: 2),
      _episode(id: 'a1', seasonNumber: 1, episodeNumber: 1),
    ]);
    expect(sorted.map((e) => e.id), ['a1', 'a2', 'b']);
  });
}
