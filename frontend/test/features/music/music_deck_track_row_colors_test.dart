import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_track_list.dart';
import 'package:omninest/features/music/presentation/widgets/music_playing_bars.dart';

/// 曲目行状态契约：播放中不使用背景条，改由动态竖条 + 主色标题表达；
/// 悬停仅保留瞬态弱 tint，普通/播放行默认透明底。
void main() {
  final track = MusicTrack(
    id: 'track-1',
    fileNodeId: '',
    title: '第一首歌',
    artistName: '歌手',
    albumTitle: '专辑',
    format: 'AUDIO',
    favorite: false,
  );
  final otherTrack = MusicTrack(
    id: 'track-2',
    fileNodeId: '',
    title: '第二首歌',
    artistName: '歌手',
    albumTitle: '专辑',
    format: 'AUDIO',
    favorite: false,
  );

  Future<void> pumpList(WidgetTester tester, {String? currentKey}) async {
    final items = [
      MusicPlayableItem.local(track),
      MusicPlayableItem.local(otherTrack),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              height: 132,
              child: MusicDeckTrackList(
                items: items,
                currentPlayableKey: currentKey,
                onPlay: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  List<Material> rowMaterials(WidgetTester tester) {
    return tester
        .widgetList<Material>(find.byType(Material))
        .where((material) => material.borderRadius is BorderRadius)
        .toList();
  }

  testWidgets('普通行与播放行均无背景条', (tester) async {
    final item = MusicPlayableItem.local(track);
    await pumpList(tester, currentKey: item.playableKey);
    final materials = rowMaterials(tester);
    expect(materials, hasLength(2));
    for (final material in materials) {
      expect(material.color, Colors.transparent);
    }
  });

  testWidgets('播放行显示动态竖条，非播放行不显示', (tester) async {
    await pumpList(tester);
    expect(find.byType(MusicPlayingBars), findsNothing);

    final item = MusicPlayableItem.local(track);
    await pumpList(tester, currentKey: item.playableKey);
    expect(find.byType(MusicPlayingBars), findsOneWidget);
  });

  testWidgets('播放行标题使用 music primary', (tester) async {
    final item = MusicPlayableItem.local(track);
    await pumpList(tester, currentKey: item.playableKey);
    final titleText = tester.widget<Text>(
      find
          .descendant(
            of: find.byType(MusicDeckTrackList),
            matching: find.text('第一首歌'),
          )
          .first,
    );
    final colors = tester.element(find.byType(MusicDeckTrackList)).musicColors;
    expect(titleText.style?.color, colors.primary);
  });
}
