import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_track_list.dart';

const MusicTrack _track = MusicTrack(
  id: 'track-1',
  fileNodeId: 'file-1',
  title: 'Menu Track',
  artistName: 'Menu Artist',
  albumTitle: 'Menu Album',
  format: 'flac',
  favorite: false,
);

void main() {
  testWidgets('曲目行菜单提供下一首播放并回调原始对象', (tester) async {
    final enqueued = <MusicPlayableItem>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: MusicDeckTrackList(
            items: [MusicPlayableItem.local(_track)],
            onPlay: (_) {},
            onEnqueue: enqueued.add,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一首播放'));
    await tester.pumpAndSettle();

    expect(enqueued, hasLength(1));
    expect(enqueued.single.track.title, 'Menu Track');
  });

  testWidgets('曲目行菜单提供加入歌单并回调原始对象', (tester) async {
    final added = <MusicPlayableItem>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: MusicDeckTrackList(
            items: [MusicPlayableItem.local(_track)],
            onPlay: (_) {},
            onAddToPlaylist: added.add,
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.more_vert_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('加入歌单'));
    await tester.pumpAndSettle();

    expect(added, hasLength(1));
    expect(added.single.track.title, 'Menu Track');
  });

  testWidgets('未提供回调的曲目行不渲染更多菜单', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: MusicDeckTrackList(
            items: [MusicPlayableItem.local(_track)],
            onPlay: (_) {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
  });
}
