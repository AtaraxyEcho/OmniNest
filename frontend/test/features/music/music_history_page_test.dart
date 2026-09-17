import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_history_controller.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/data/music_playback_queue_store.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/pages/music_history_page.dart';

void main() {
  testWidgets('播放历史页按日分组展示并触底加载下一页', (tester) async {
    final api = _HistoryApiStub();
    final container = ProviderContainer.test(
      overrides: [
        musicApiProvider.overrideWithValue(api),
        musicPlaybackQueueOwnerIdProvider.overrideWith((ref) async => 'user-a'),
        musicPlaybackQueueStoreProvider.overrideWithValue(_MemoryStore()),
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
          home: const MusicHistoryPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('今天'), findsOneWidget);
    expect(find.text('昨天'), findsOneWidget);
    expect(find.text('History Local'), findsOneWidget);
    expect(find.text('History Online'), findsOneWidget);

    // 触底加载第二页
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('History Page2'), findsOneWidget);
  });

  test('loadMore 跨页去重后停止', () async {
    final api = _HistoryApiStub();
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final state = await container.read(musicHistoryControllerProvider.future);

    expect(state.groups, hasLength(2));
    expect(state.hasMore, isTrue);

    await container.read(musicHistoryControllerProvider.notifier).loadMore();
    // 已到尾部后再次调用应提前返回，不再发请求。
    await container.read(musicHistoryControllerProvider.notifier).loadMore();
    final next = container.read(musicHistoryControllerProvider).asData!.value;

    expect(next.loadedCount, 3);
    expect(next.hasMore, isFalse);
    expect(api.requestedPages, [0, 1]);
  });
}

class _MemoryStore implements MusicPlaybackQueueStore {
  @override
  Future<MusicPlaybackQueueSnapshot?> load(String ownerId) async => null;

  @override
  Future<void> save(
    String ownerId,
    MusicPlaybackQueueSnapshot snapshot,
  ) async {}
}

class _HistoryApiStub implements MusicApi {
  final requestedPages = <int>[];
  // 固定为「今天中午 / 昨天 / 前天」，避免贴近午夜时 now-2h 落入昨日导致分组与预期不符。
  late final DateTime todayNoon = () {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day, 12);
  }();
  late final DateTime yesterdayNoon = todayNoon.subtract(const Duration(days: 1));
  late final DateTime dayBeforeNoon = todayNoon.subtract(const Duration(days: 2));

  List<MusicPlayHistoryEntry> _page(int page) {
    switch (page) {
      case 0:
        return [
          MusicPlayHistoryEntry(
            playableKey: 'local:track-1',
            title: 'History Local',
            artistName: 'Artist A',
            playedAt: todayNoon,
          ),
          MusicPlayHistoryEntry(
            playableKey: 'online:netease:888',
            title: 'History Online',
            artistName: 'Artist B',
            playedAt: yesterdayNoon,
          ),
        ];
      case 1:
        return [
          MusicPlayHistoryEntry(
            playableKey: 'local:track-3',
            title: 'History Page2',
            artistName: 'Artist C',
            playedAt: dayBeforeNoon,
          ),
          MusicPlayHistoryEntry(
            playableKey: 'local:track-1',
            title: 'History Local',
            artistName: 'Artist A',
            // 与首页重复的条目（同 key 同时间），应被去重
            playedAt: todayNoon,
          ),
        ];
      default:
        return const [];
    }
  }

  @override
  Future<MusicPagedResult<MusicPlayHistoryEntry>> playHistory({
    int page = 0,
    int size = 50,
  }) async {
    requestedPages.add(page);
    final items = _page(page);
    return MusicPagedResult<MusicPlayHistoryEntry>(
      items: items,
      page: page,
      size: size,
      totalElements: 3,
    );
  }

  @override
  Future<MusicDashboard> dashboard() async => MusicDashboard.empty();

  @override
  Future<MusicPagedResult<MusicTrack>> tracks({
    int page = 0,
    int size = 100,
    String sort = 'title,asc',
  }) async => const MusicPagedResult<MusicTrack>(items: <MusicTrack>[]);

  @override
  Future<MusicPagedResult<MusicAlbum>> albums({
    int page = 0,
    int size = 100,
    String sort = 'updatedAt,desc',
  }) async => const MusicPagedResult<MusicAlbum>(items: <MusicAlbum>[]);

  @override
  Future<MusicPagedResult<MusicArtist>> artists({
    int page = 0,
    int size = 100,
    String sort = 'name,asc',
  }) async => const MusicPagedResult<MusicArtist>(items: <MusicArtist>[]);

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
  Future<void> savePlaybackQueue(MusicPlaybackQueueSnapshot snapshot) async {}

  @override
  Future<PlatformUserInfo?> platformInfo(String platform) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
