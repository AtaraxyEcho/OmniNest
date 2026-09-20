import 'package:flutter/gestures.dart' show kLongPressTimeout, kPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/data/music_playback_queue_store.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_queue_sheet.dart';

const List<MusicTrack> _tracks = <MusicTrack>[
  MusicTrack(
    id: 'track-1',
    fileNodeId: 'file-1',
    title: 'Queue Alpha',
    artistName: 'Artist A',
    albumTitle: 'Album A',
    format: 'flac',
    favorite: false,
  ),
  MusicTrack(
    id: 'track-2',
    fileNodeId: 'file-2',
    title: 'Queue Beta',
    artistName: 'Artist B',
    albumTitle: 'Album B',
    format: 'mp3',
    favorite: false,
  ),
  MusicTrack(
    id: 'track-3',
    fileNodeId: 'file-3',
    title: 'Queue Gamma',
    artistName: 'Artist C',
    albumTitle: 'Album C',
    format: 'mp3',
    favorite: false,
  ),
];

void main() {
  testWidgets('队列抽屉支持拖拽把手调整顺序', (tester) async {
    final harness = await _pumpQueueSheet(tester);

    final firstHandle = find.byType(ReorderableDragStartListener).first;
    debugPrint(
      'view: ${tester.view.physicalSize} / ${tester.view.devicePixelRatio}',
    );

    final gesture = await tester.startGesture(
      tester.getCenter(firstHandle),
      pointer: 7,
    );
    await tester.pump(kLongPressTimeout + kPressTimeout);
    // 单次大位移会级联交换，首行直接拖到队尾验证后移换算。
    await gesture.moveTo(tester.getCenter(firstHandle) + const Offset(0, 200));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));

    final state = harness.container.read(musicCenterControllerProvider);
    expect(
      state.asData!.value.playbackItems
          .map((item) => item.track.title)
          .toList(),
      ['Queue Beta', 'Queue Gamma', 'Queue Alpha'],
    );
  });

  testWidgets('队列抽屉支持把队尾曲目前移一行', (tester) async {
    final harness = await _pumpQueueSheet(tester);

    final lastHandle = find.byType(ReorderableDragStartListener).last;
    final gesture = await tester.startGesture(
      tester.getCenter(lastHandle),
      pointer: 7,
    );
    await tester.pump(kLongPressTimeout + kPressTimeout);
    final start = tester.getCenter(lastHandle);
    await gesture.moveTo(start - const Offset(0, 70));
    await tester.pump();
    await gesture.moveTo(start - const Offset(0, 130));
    await tester.pump();
    await gesture.moveTo(start - const Offset(0, 175));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));

    final state = harness.container.read(musicCenterControllerProvider);
    expect(
      state.asData!.value.playbackItems
          .map((item) => item.track.title)
          .toList(),
      ['Queue Alpha', 'Queue Gamma', 'Queue Beta'],
    );
  });

  testWidgets('队列条目左滑删除并同步应用状态', (tester) async {
    final harness = await _pumpQueueSheet(tester);

    await tester.drag(find.text('Queue Beta'), const Offset(-480, 0));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Queue Beta'), findsNothing);
    final state = harness.container.read(musicCenterControllerProvider);
    expect(state.asData!.value.playbackItems.map((item) => item.track.title), [
      'Queue Alpha',
      'Queue Gamma',
    ]);
  });

  testWidgets('清空按钮停止播放并展示空态', (tester) async {
    final harness = await _pumpQueueSheet(tester);

    await tester.tap(find.text('清空队列'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('播放队列为空'), findsOneWidget);
    final state = harness.container.read(musicCenterControllerProvider);
    final value = state.asData!.value;
    expect(value.playbackItems, isEmpty);
    expect(value.playbackIndex, -1);
    expect(value.isPlaying, isFalse);
    expect(value.currentItem, isNotNull);
  });

  testWidgets('清空按钮在空队列时禁用', (tester) async {
    await _pumpQueueSheet(tester, snapshotItems: false);

    final button = tester.widget<TextButton>(
      find.ancestor(of: find.text('清空队列'), matching: find.byType(TextButton)),
    );
    expect(button.onPressed, isNull);
  });
}

Future<_QueueSheetHarness> _pumpQueueSheet(
  WidgetTester tester, {
  bool snapshotItems = true,
}) async {
  final api = _StubMusicApi(
    queueSnapshot: MusicPlaybackQueueSnapshot(
      items:
          snapshotItems
              ? _tracks.map(MusicPlayableItem.local).toList(growable: false)
              : const <MusicPlayableItem>[],
      currentIndex: 0,
    ),
  );
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
        home: const Scaffold(body: MusicDeckQueueSheet()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _QueueSheetHarness(container);
}

class _QueueSheetHarness {
  const _QueueSheetHarness(this.container);

  final ProviderContainer container;
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
  _StubMusicApi({required this.queueSnapshot});

  MusicPlaybackQueueSnapshot queueSnapshot;

  @override
  Future<MusicDashboard> dashboard() async => MusicDashboard.empty();

  @override
  Future<MusicPagedResult<MusicTrack>> tracks({
    int page = 0,
    int size = 100,
    String sort = 'title,asc',
  }) async => MusicPagedResult<MusicTrack>(items: _tracks);

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
  Future<MusicPlaybackQueueSnapshot> playbackQueue() async => queueSnapshot;

  @override
  Future<MusicPlaybackQueueSnapshot> savePlaybackQueue(
    MusicPlaybackQueueSnapshot snapshot,
  ) async => snapshot;

  @override
  Future<PlatformUserInfo?> platformInfo(String platform) async => null;

  @override
  Future<MusicPlaybackPlan> playbackPlan(String trackId) async =>
      MusicPlaybackPlan(
        trackId: trackId,
        url: 'http://localhost/$trackId.flac',
        durationSeconds: 200,
        format: 'flac',
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
