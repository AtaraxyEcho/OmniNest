import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/data/music_playback_queue_store.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/pages/music_metadata_edit_page.dart';

const MusicTrack _track = MusicTrack(
  id: 'track-1',
  fileNodeId: 'file-1',
  title: 'Raw Filename',
  artistName: 'Unknown Artist',
  albumTitle: 'Unknown Album',
  format: 'flac',
  favorite: false,
);

const MusicScrapeCandidate _candidate = MusicScrapeCandidate(
  provider: 'netease',
  externalId: '199',
  title: 'Matched Title',
  artistName: 'Matched Artist',
  albumTitle: 'Matched Album',
  durationSeconds: 245,
  trackNumber: 3,
  score: 92,
);

const MusicTrack _appliedTrack = MusicTrack(
  id: 'track-1',
  fileNodeId: 'file-1',
  title: 'Matched Title',
  artistName: 'Matched Artist',
  albumTitle: 'Matched Album',
  format: 'flac',
  favorite: false,
);

const MusicTrack _trackWithLyrics = MusicTrack(
  id: 'track-1',
  fileNodeId: 'file-1',
  title: 'Raw Filename',
  artistName: 'Unknown Artist',
  albumTitle: 'Unknown Album',
  format: 'flac',
  favorite: false,
  lyricsRaw: '[00:01.00] Existing line',
);

const MusicTrack _trackWithCoverAndLyrics = MusicTrack(
  id: 'track-1',
  fileNodeId: 'file-1',
  title: 'Raw Filename',
  artistName: 'Unknown Artist',
  albumTitle: 'Unknown Album',
  format: 'flac',
  favorite: false,
  coverUrl: '/api/v1/music/covers/cover-1',
  lyricsRaw: '[00:01.00] Existing line',
);

void main() {
  testWidgets('在线匹配展示候选并应用后回填表单', (tester) async {
    final api = _StubMusicApi();
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
        musicPlaybackQueueStoreProvider.overrideWithValue(
          _MemoryMusicPlaybackQueueStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const MusicMetadataEditPage(trackId: 'track-1'),
        ),
      ),
    );
    await container.read(musicCenterControllerProvider.future);
    await tester.pumpAndSettle();

    expect(find.text('Raw Filename'), findsWidgets);
    expect(find.text('Matched Title'), findsNothing);

    await tester.tap(find.text('在线匹配'));
    await tester.pumpAndSettle();

    expect(find.text('匹配候选'), findsOneWidget);
    expect(find.text('Matched Title'), findsOneWidget);
    expect(find.text('Matched Artist · Matched Album'), findsOneWidget);

    await tester.ensureVisible(find.text('应用'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    expect(api.appliedScrapeTrackIds, ['track-1']);
    expect(find.text('已应用匹配元数据'), findsOneWidget);
    final titleField = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Matched Title'),
    );
    expect(titleField.controller?.text, 'Matched Title');
  });

  testWidgets('搜索歌词预览后应用并展示成功反馈', (tester) async {
    final api = _StubMusicApi();
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
        musicPlaybackQueueStoreProvider.overrideWithValue(
          _MemoryMusicPlaybackQueueStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const MusicMetadataEditPage(trackId: 'track-1'),
        ),
      ),
    );
    await container.read(musicCenterControllerProvider.future);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('搜索歌词'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索歌词'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('应用歌词'), findsOneWidget);
    expect(find.text('[00:01.00] First line'), findsOneWidget);

    await tester.tap(find.text('应用歌词'));
    await tester.pumpAndSettle();

    expect(api.appliedLyricsTrackIds, ['track-1']);
    expect(api.appliedLyricsTexts.single, '[00:01.00] First line');
    expect(find.text('歌词已应用到「Matched Title」'), findsOneWidget);
    // 按钮文件名与歌词状态区各展示一次来源标签。
    expect(find.text('在线歌词'), findsNWidgets(2));
  });

  testWidgets('列表投影缺歌词时补拉详情并预览已有歌词', (tester) async {
    final api = _StubMusicApi()..trackDetailResult = _trackWithLyrics;
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
        musicPlaybackQueueStoreProvider.overrideWithValue(
          _MemoryMusicPlaybackQueueStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const MusicMetadataEditPage(trackId: 'track-1'),
        ),
      ),
    );
    await container.read(musicCenterControllerProvider.future);
    await tester.pumpAndSettle();

    expect(api.trackDetailRequests, ['track-1']);
    expect(find.text('已有歌词（可替换）'), findsOneWidget);
    expect(find.textContaining('[00:01.00] Existing line'), findsWidgets);
  });

  testWidgets('移除封面与清空歌词保存时提交 clearCover 与空歌词', (tester) async {
    final api = _StubMusicApi()..currentTracks = const [_trackWithCoverAndLyrics];
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
        musicPlaybackQueueStoreProvider.overrideWithValue(
          _MemoryMusicPlaybackQueueStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const MusicMetadataEditPage(trackId: 'track-1'),
        ),
      ),
    );
    await container.read(musicCenterControllerProvider.future);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('清空歌词'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空歌词'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('移除封面'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除封面'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(api.updatedTrackClearCover, isTrue);
    expect(api.updatedTrackLyricsRaw, '');
  });

  testWidgets('列表投影已带歌词时直接预览且不重复补拉', (tester) async {
    final api =
        _StubMusicApi()
          ..currentTracks = const [_trackWithLyrics]
          ..trackDetailResult = _trackWithLyrics;
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
        musicPlaybackQueueStoreProvider.overrideWithValue(
          _MemoryMusicPlaybackQueueStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const MusicMetadataEditPage(trackId: 'track-1'),
        ),
      ),
    );
    await container.read(musicCenterControllerProvider.future);
    await tester.pumpAndSettle();

    expect(api.trackDetailRequests, isEmpty);
    expect(find.text('已有歌词（可替换）'), findsOneWidget);
    expect(find.textContaining('[00:01.00] Existing line'), findsWidgets);
  });
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

class _StubMusicApi implements MusicApi {
  final scrapeCandidateTrackIds = <String>[];
  final appliedScrapeTrackIds = <String>[];
  final trackDetailRequests = <String>[];
  List<MusicTrack> currentTracks = const [_track];
  MusicTrack? trackDetailResult;

  @override
  Future<MusicTrack> trackDetail(String trackId) async {
    trackDetailRequests.add(trackId);
    final detail = trackDetailResult;
    if (detail != null) {
      return detail;
    }
    return currentTracks.firstWhere((track) => track.id == trackId);
  }

  @override
  Future<MusicDashboard> dashboard() async => MusicDashboard.empty();

  @override
  Future<MusicPagedResult<MusicTrack>> tracks({
    int page = 0,
    int size = 100,
    String sort = 'title,asc',
  }) async => MusicPagedResult<MusicTrack>(items: currentTracks);

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
  Future<List<MusicPlaylist>> playlists() async => const <MusicPlaylist>[];

  @override
  Future<List<MusicRecentEntry>> recentItems() async =>
      const <MusicRecentEntry>[];

  @override
  Future<MusicTrack?> lastPlayed() async => null;

  @override
  Future<MusicPlaybackQueueSnapshot> playbackQueue() async =>
      const MusicPlaybackQueueSnapshot();

  @override
  Future<MusicPlaybackQueueSnapshot> savePlaybackQueue(
    MusicPlaybackQueueSnapshot snapshot,
  ) async => snapshot;

  @override
  Future<PlatformUserInfo?> platformInfo(String platform) async => null;

  final appliedLyricsTrackIds = <String>[];
  final appliedLyricsTexts = <String>[];
  bool updatedTrackClearCover = false;
  String? updatedTrackLyricsRaw;

  @override
  Future<void> updateTrack({
    required String trackId,
    String? title,
    String? artistName,
    String? albumTitle,
    String? genre,
    String? lyricsRaw,
    String? coverFileId,
    bool clearCover = false,
  }) async {
    updatedTrackClearCover = clearCover;
    updatedTrackLyricsRaw = lyricsRaw;
  }

  @override
  Future<MusicLyricsResult?> searchLyrics(String trackId) async =>
      const MusicLyricsResult(
        syncedLyrics: '[00:01.00] First line',
        trackName: 'Raw Filename',
        artistName: 'Unknown Artist',
      );

  @override
  Future<MusicTrack> applyLyrics(
    String trackId,
    String lyrics, {
    String? lyricsTranslation,
  }) async {
    appliedLyricsTrackIds.add(trackId);
    appliedLyricsTexts.add(lyrics);
    return _appliedTrack;
  }

  @override
  Future<List<MusicScrapeCandidate>> scrapeCandidates(String trackId) async {
    scrapeCandidateTrackIds.add(trackId);
    return const [_candidate];
  }

  @override
  Future<MusicTrack> applyScrapeCandidate(
    String trackId,
    MusicScrapeCandidate candidate,
  ) async {
    appliedScrapeTrackIds.add(trackId);
    currentTracks = const [_appliedTrack];
    return _appliedTrack;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
