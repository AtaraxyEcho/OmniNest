import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/feature/music_colors.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_track_list.dart';

/// 曲目行状态色契约：播放行为持久激活态（playingRowBg 权重高于悬停），
/// 选中分支优先于悬停反馈，普通行保持透明。
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

  /// 混合后不透明度权重对比：以 a 通道（0-255）近似强度阶梯。
  int weight(MusicColors colors, Color value) => (value.a * 255).round();

  MusicColors colorsOf(WidgetTester tester) {
    return tester.element(find.byType(MusicDeckTrackList)).musicColors;
  }

  List<Material> rowMaterials(WidgetTester tester) {
    return tester
        .widgetList<Material>(find.byType(Material))
        .where((material) => material.borderRadius is BorderRadius)
        .toList();
  }

  Future<void> pumpList(
    WidgetTester tester,
    Brightness brightness, {
    String? currentKey,
  }) async {
    final item = MusicPlayableItem.local(track);
    await tester.pumpWidget(
      MaterialApp(
        theme:
            brightness == Brightness.light
                ? OmniNestTheme.light()
                : OmniNestTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 800,
              height: 132,
              child: MusicDeckTrackList(
                items: [item, item],
                currentPlayableKey: currentKey,
                onPlay: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('深色主题：播放行为 music primary @ 24% 且权重高于悬停 tint', (tester) async {
    await pumpList(tester, Brightness.dark);
    final colors = colorsOf(tester);
    // Music 模块专属主色（非全局 primary）叠加 24% alpha（withValues 浮点精度，
    // RGB 通道逐位相等、alpha 用浮点近似断言）。
    const primary = Color(0xFF8BD9D5);
    expect(
      colors.playingRowBg.toARGB32() & 0x00FFFFFF,
      primary.toARGB32() & 0x00FFFFFF,
    );
    expect(colors.playingRowBg.a, moreOrLessEquals(0.24, epsilon: 0.001));
    expect(
      weight(colors, colors.playingRowBg),
      greaterThan(weight(colors, colors.hoverBg)),
    );
    // 普通行保持透明底。
    final materials = rowMaterials(tester);
    expect(materials, hasLength(2));
    for (final material in materials) {
      expect(material.color, Colors.transparent);
    }
  });

  testWidgets('浅色主题：播放行为 music primary @ 14% 且权重高于悬停 tint', (tester) async {
    await pumpList(tester, Brightness.light);
    final colors = colorsOf(tester);
    const primary = Color(0xFF176B72);
    expect(
      colors.playingRowBg.toARGB32() & 0x00FFFFFF,
      primary.toARGB32() & 0x00FFFFFF,
    );
    expect(colors.playingRowBg.a, moreOrLessEquals(0.14, epsilon: 0.001));
    expect(
      weight(colors, colors.playingRowBg),
      greaterThan(weight(colors, colors.hoverBg)),
    );
  });

  testWidgets('播放行选中分支优先于悬停反馈', (tester) async {
    final item = MusicPlayableItem.local(track);
    await pumpList(tester, Brightness.dark, currentKey: item.playableKey);
    final colors = colorsOf(tester);
    final material = rowMaterials(tester).first;
    expect(material.color, colors.playingRowBg);
  });
}
