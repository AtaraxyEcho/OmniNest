import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/control_tokens.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_playable_item.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_cover_grid.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_layout.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_primitives.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_search.dart';
import 'package:omninest/features/music/presentation/deck/music_deck_track_list.dart';

void main() {
  test('首页继续聆听固定五首且不创建内部滚动区', () {
    final source =
        File(
          'lib/features/music/presentation/deck/music_deck_content.dart',
        ).readAsStringSync();

    expect(source, contains('_homeContinueListeningLimit = 5'));
    expect(source, contains('.take(_homeContinueListeningLimit)'));
    expect(source, contains('scrollable: false'));
  });

  testWidgets('封面网格在主要窗口宽度下不会溢出', (tester) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    final items = List<MusicDeckCoverItem>.generate(
      12,
      (index) => MusicDeckCoverItem(
        id: 'item-$index',
        title: 'Track $index',
        subtitle: 'Artist $index',
        onTap: () {},
      ),
    );

    for (final width in <double>[360, 760, 1440, 2560, 3840]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(
        MaterialApp(
          theme: _testTheme(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: MusicDeckCoverGrid(items: items),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '窗口宽度 $width 出现布局异常');
      expect(find.byType(MusicDeckCoverGrid), findsOneWidget);
    }
  });

  testWidgets('桌面歌单卡片悬停后显示管理菜单', (tester) async {
    var edited = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: _testTheme(TargetPlatform.windows),
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 280,
            child: MusicDeckCoverGrid(
              items: [
                MusicDeckCoverItem(
                  id: 'local-playlist',
                  title: 'Focus',
                  subtitle: '12 tracks',
                  onTap: () {},
                  actions: [
                    MusicDeckCoverAction(
                      label: 'Edit',
                      icon: Icons.edit_outlined,
                      onSelected: () => edited = true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('Focus')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));

    expect(edited, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('移动端歌单卡片通过长按显示管理操作', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _testTheme(TargetPlatform.android),
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 280,
            child: MusicDeckCoverGrid(
              items: [
                MusicDeckCoverItem(
                  id: 'local-playlist',
                  title: 'Focus',
                  subtitle: '12 tracks',
                  onTap: () {},
                  actions: [
                    MusicDeckCoverAction(
                      label: 'Delete',
                      icon: Icons.delete_outline,
                      destructive: true,
                      onSelected: () {},
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byType(PopupMenuButton<int>), findsNothing);
    await tester.longPress(find.text('Focus'));
    await tester.pumpAndSettle();

    expect(find.text('Delete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有管理操作的外部歌单不显示菜单', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _testTheme(TargetPlatform.windows),
        localizationsDelegates: _localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 280,
            child: MusicDeckCoverGrid(
              items: [
                MusicDeckCoverItem(
                  id: 'netease-playlist',
                  title: 'Cloud Mix',
                  subtitle: 'Netease',
                  platform: MusicPlatform.netease,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byType(PopupMenuButton<int>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('每日推荐卡片的平台标签固定在右上角', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: _testTheme(TargetPlatform.windows),
        localizationsDelegates: _localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 280,
            child: MusicDeckCoverGrid(
              items: [
                MusicDeckCoverItem(
                  id: 'daily-recommendation',
                  title: 'Daily recommended tracks',
                  subtitle: '30 tracks',
                  platform: MusicPlatform.netease,
                  overlayPlatformBadge: true,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final badge = find.byType(MusicDeckSourceBadge);
    expect(badge, findsOneWidget);
    expect(tester.widget<MusicDeckSourceBadge>(badge).overlay, isTrue);
    final positioned = tester.widget<Positioned>(
      find.ancestor(of: badge, matching: find.byType(Positioned)),
    );
    expect(positioned.top, 8);
    expect(positioned.right, 8);
  });

  testWidgets('歌曲列表通过整行点击播放且左侧不显示播放按钮', (tester) async {
    var playedIndex = -1;
    await tester.pumpWidget(
      MaterialApp(
        theme: _testTheme(),
        localizationsDelegates: _localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MusicDeckTrackList(
            items: [
              MusicPlayableItem.local(
                const MusicTrack(
                  id: 'track-1',
                  fileNodeId: 'file-1',
                  title: 'Track',
                  artistName: 'Artist',
                  albumTitle: 'Album',
                  format: 'flac',
                  favorite: false,
                ),
              ),
            ],
            onPlay: (index) => playedIndex = index,
          ),
        ),
      ),
    );

    expect(find.byType(IconButton), findsNothing);
    await tester.tap(find.text('Track'));
    expect(playedIndex, 0);
  });

  test('桌面布局在超宽屏上扩展主内容区并限制辅助控件宽度', () {
    final standard = MusicDeckDesktopLayout.resolve(1440);
    final wide = MusicDeckDesktopLayout.resolve(2560);
    final ultraWide = MusicDeckDesktopLayout.resolve(3840);

    expect(standard.showWidePanel, isFalse);
    expect(wide.showWidePanel, isTrue);
    expect(ultraWide.mainContentWidth, greaterThan(wide.mainContentWidth));
    expect(ultraWide.mainContentWidth, greaterThan(2800));
    // 左右侧卡统一宽度与间距，不再随视口放大。
    expect(ultraWide.widePanelWidth, MusicDeckDesktopLayout.sideCardWidth);
    expect(ultraWide.navigationWidth, MusicDeckDesktopLayout.sideCardWidth);
    // 岛与中内容列同宽，只保留上限：不再按比例收缩，也没有 920 下限，
    // 否则侧卡下探到底线后两侧留白会露出岛没占满带宽。
    expect(standard.playerMaxWidth, MusicDeckDesktopLayout.islandMaxWidth);
    expect(ultraWide.playerMaxWidth, MusicDeckDesktopLayout.islandMaxWidth);
    // 搜索框上限与其他模块顶栏搜索令牌一致,不再随视口放宽。
    expect(ultraWide.searchMaxWidth, AppControlTokens.searchFieldWidth);
  });

  test('高 DPI 缩放档最大化窗口仍显示右侧正在播放卡', () {
    // Windows 4K@250% 缩放的最大化逻辑宽度为 1536。
    final scaled = MusicDeckDesktopLayout.resolve(1536);
    expect(scaled.showWidePanel, isTrue);
    expect(scaled.compactNavigation, isFalse);
    expect(scaled.mainContentWidth, greaterThan(600), reason: '三卡并存时主内容区仍需可用');
  });

  test('桌面布局在最小桌面宽度下仍保留有效主内容区', () {
    final layout = MusicDeckDesktopLayout.resolve(760);

    expect(layout.compactNavigation, isTrue);
    expect(layout.showWidePanel, isFalse);
    expect(layout.mainContentWidth, greaterThan(600));
  });

  testWidgets('浅色模式搜索框使用主题容器色而不是纯白背景', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.light(),
        localizationsDelegates: _localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MusicDeckSearchField(
            controller: controller,
            focusNode: focusNode,
            sources: const <MusicPlatform>{MusicPlatform.local},
            onChanged: (_) {},
            onFocusChanged: (_) {},
          ),
        ),
      ),
    );

    final surface = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey<String>('music-global-search-surface')),
    );
    final decoration = surface.decoration as BoxDecoration;
    expect(decoration.color, isNotNull);
    expect(decoration.color, isNot(Colors.white));
  });
}

ThemeData _testTheme([TargetPlatform? platform]) {
  return ThemeData.dark().copyWith(
    platform: platform,
    splashFactory: InkRipple.splashFactory,
  );
}

const _localizationsDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];
