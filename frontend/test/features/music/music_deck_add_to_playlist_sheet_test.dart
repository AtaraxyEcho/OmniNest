import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/music/application/music_controller.dart';
import 'package:omninest/features/music/data/music_api.dart';
import 'package:omninest/features/music/data/music_playback_queue_store.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_add_to_playlist_sheet.dart';

const MusicTrack _track = MusicTrack(
  id: 'track-1',
  fileNodeId: 'file-1',
  title: 'Sheet Track',
  artistName: 'Sheet Artist',
  albumTitle: 'Sheet Album',
  format: 'flac',
  favorite: false,
);

const MusicPlaylist _playlist = MusicPlaylist(
  id: 'playlist-1',
  name: 'Road Trip',
  playlistType: 'CUSTOM',
  trackCount: 3,
);

void main() {
  testWidgets('选中歌单后调用加曲命令并给出成功反馈', (tester) async {
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
          home: Scaffold(
            body: MusicDeckAddToPlaylistSheet(
              item: MusicPlayableItem.local(_track),
              onDismissed: _noop,
            ),
          ),
        ),
      ),
    );
    await container.read(musicCenterControllerProvider.future);
    await tester.pumpAndSettle();

    expect(find.text('Road Trip'), findsOneWidget);
    expect(find.text('新建歌单'), findsOneWidget);

    await tester.tap(find.text('Road Trip'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));

    expect(api.addedPlaylistItems['playlist-1'], ['track-1']);
    expect(find.text('已加入「Road Trip」'), findsOneWidget);
  });
}

void _noop() {}

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
  final addedPlaylistItems = <String, List<String>>{};

  @override
  Future<MusicDashboard> dashboard() async => MusicDashboard.empty();

  @override
  Future<MusicPagedResult<MusicTrack>> tracks({int page = 0, int size = 100, String sort = 'title,asc'}) async =>
      MusicPagedResult<MusicTrack>(items: const [_track]);

  @override
  Future<MusicPagedResult<MusicAlbum>> albums({int page = 0, int size = 100, String sort = 'updatedAt,desc'}) async =>
      const MusicPagedResult<MusicAlbum>(items: <MusicAlbum>[], page: 0, size: 0, totalElements: 0);

  @override
  Future<MusicPagedResult<MusicArtist>> artists({int page = 0, int size = 100, String sort = 'name,asc'}) async =>
      const MusicPagedResult<MusicArtist>(items: <MusicArtist>[], page: 0, size: 0, totalElements: 0);

  @override
  Future<List<MusicPlaylist>> playlists() async => const [_playlist];

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
  Future<MusicPlaylist> addPlaylistItems(
    String playlistId,
    List<String> trackIds,
  ) async {
    addedPlaylistItems[playlistId] = List<String>.of(trackIds);
    return _playlist.copyWith(
      trackCount: _playlist.trackCount + trackIds.length,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
