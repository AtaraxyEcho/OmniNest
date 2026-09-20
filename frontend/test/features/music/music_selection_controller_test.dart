import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/application/music_selection_controller.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_track_list.dart';

const List<MusicTrack> _tracks = <MusicTrack>[
  MusicTrack(
    id: 'track-1',
    fileNodeId: 'file-1',
    title: 'Batch Alpha',
    artistName: 'Artist',
    albumTitle: 'Album',
    format: 'flac',
    favorite: false,
  ),
  MusicTrack(
    id: 'track-2',
    fileNodeId: 'file-2',
    title: 'Batch Beta',
    artistName: 'Artist',
    albumTitle: 'Album',
    format: 'mp3',
    favorite: false,
  ),
  MusicTrack(
    id: 'track-3',
    fileNodeId: 'file-3',
    title: 'Batch Gamma',
    artistName: 'Artist',
    albumTitle: 'Album',
    format: 'mp3',
    favorite: false,
  ),
];

void main() {
  test('selection controller toggles, selects all and clears', () {
    final container = ProviderContainer.test();
    addTearDown(container.dispose);
    final notifier = container.read(musicSelectionControllerProvider.notifier);

    notifier.enterSelectionMode('track-1');
    expect(container.read(musicSelectionControllerProvider).selectedIds, {
      'track-1',
    });

    notifier.toggle('track-2');
    notifier.toggle('track-1');
    expect(container.read(musicSelectionControllerProvider).selectedIds, {
      'track-2',
    });

    notifier.selectAll(_tracks.map((track) => track.id));
    expect(
      container.read(musicSelectionControllerProvider).selectedIds,
      hasLength(3),
    );

    // 连续 toggle 两次应回到原选中状态（防重复点击破坏状态）。
    notifier.toggle('track-3');
    notifier.toggle('track-3');
    expect(
      container.read(musicSelectionControllerProvider).selectedIds,
      hasLength(3),
    );

    notifier.exitSelectionMode();
    final exited = container.read(musicSelectionControllerProvider);
    expect(exited.selectionMode, isFalse);
    expect(exited.selectedIds, isEmpty);
  });

  testWidgets('长按进入多选后点击行切换选中', (tester) async {
    MusicSelectionState? latest;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              latest = ref.watch(musicSelectionControllerProvider);
              return Scaffold(
                body: MusicDeckTrackList(
                  items: _tracks.map(MusicPlayableItem.local).toList(),
                  onPlay: (index) {
                    if (latest!.selectionMode) {
                      ref
                          .read(musicSelectionControllerProvider.notifier)
                          .toggle(_tracks[index].id);
                    }
                  },
                  onLongPress:
                      () => ref
                          .read(musicSelectionControllerProvider.notifier)
                          .enterSelectionMode('track-1'),
                  selectedIds:
                      latest == null
                          ? null
                          : (latest!.selectionMode
                              ? latest!.selectedIds
                              : null),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.longPress(find.text('Batch Alpha'));
    await tester.pumpAndSettle();
    expect(latest!.selectionMode, isTrue);
    expect(latest!.selectedIds, {'track-1'});

    await tester.dragUntilVisible(
      find.text('Batch Gamma'),
      find.byType(ListView),
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Batch Gamma'));
    await tester.pumpAndSettle();
    expect(latest!.selectedIds, {'track-1', 'track-3'});
  });

  test('批量下一首播放逐项入队', () async {
    final container = ProviderContainer.test(
      overrides: [musicApiProvider.overrideWithValue(_BatchApiStub())],
    );
    addTearDown(container.dispose);
    await container.read(musicCenterControllerProvider.future);
    final notifier = container.read(musicSelectionControllerProvider.notifier);
    notifier.enterSelectionMode('track-1');
    notifier.toggle('track-2');

    final results = notifier.enqueueSelected(_tracks);
    expect(results, hasLength(2));
    expect(results.every((item) => item.success), isTrue);
    final center = container.read(musicCenterControllerProvider).asData!.value;
    expect(center.playbackItems, hasLength(2));
  });
}

class _BatchApiStub implements MusicApi {
  @override
  Future<MusicPagedResult<MusicTrack>> tracks({
    int page = 0,
    int size = 100,
    String sort = 'title,asc',
  }) async => MusicPagedResult<MusicTrack>(items: _tracks);

  @override
  Future<MusicDashboard> dashboard() async => MusicDashboard.empty();

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
  Future<MusicPlaybackQueueSnapshot> savePlaybackQueue(
    MusicPlaybackQueueSnapshot snapshot,
  ) async => snapshot;

  @override
  Future<PlatformUserInfo?> platformInfo(String platform) async => null;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
