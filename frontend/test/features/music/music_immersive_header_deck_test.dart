import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_player.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_style.dart';

void main() {
  test('Music 沉浸顶部栏保留 F11 作用域，Portal 不得绑定 F11', () {
    final musicSource =
        File(
          'lib/features/music/presentation/player/music_immersive_overlay.dart',
        ).readAsStringSync();
    final portalSource =
        File(
          'lib/features/portal/presentation/widgets/portal_desktop_visual_shells.dart',
        ).readAsStringSync();

    expect(musicSource, contains('AppFullscreenShortcutScope'));
    expect(musicSource, contains('AppFullscreenButton'));
    expect(musicSource, contains('reservedTopInset: safeTop + 58'));
    // F11 由 app.dart 全局处理器统一分发为无边框全屏；portal 壳层若再绑定
    // F11 会与全局处理器同一按键双重触发（全屏与沉浸模式同时翻转）。
    expect(portalSource, isNot(contains('AppFullscreenShortcutScope')));
    expect(portalSource, contains('AppFullscreenButton'));
    expect(portalSource, isNot(contains('_PortalImmersiveButton')));
  });

  test('沉浸顶部只显示放大的歌曲信息', () {
    final source =
        File(
          'lib/features/music/presentation/player/music_immersive_track_header.dart',
        ).readAsStringSync();

    expect(source, isNot(contains('_MusicImmersiveArtwork')));
    expect(source, isNot(contains('onTogglePlayback')));
    expect(source, contains('(27 * scale).clamp(23.0, 34.0)'));
    expect(source, contains('(16 * scale).clamp(14.0, 19.0)'));
  });

  test('沉浸右侧封面卡片保持不透明', () {
    final source =
        File(
          'lib/features/music/presentation/player/music_immersive_cover_deck.dart',
        ).readAsStringSync();

    expect(source, isNot(contains('AnimatedOpacity')));
    expect(source, isNot(contains('final opacity =')));
    expect(source, contains('palette.surfaceStrong.withValues('));
    expect(source, contains('alpha: 1'));
  });

  test('沉浸右侧封面卡片使用独立指针跟踪', () {
    final source =
        File(
          'lib/features/music/presentation/player/music_immersive_cover_deck.dart',
        ).readAsStringSync();

    expect(source, contains('_dragPointer'));
    expect(source, contains('_handlePointerMove'));
    expect(source, contains('SystemMouseCursors.grabbing'));
    expect(source, contains('_dominantDrag'));
    expect(source, contains('_resolveDragDelta'));
    expect(source, contains('_deckPaintOrder = <int>[4, 3, 2, 1]'));
    expect(source, contains('_buildActiveDeckCard()'));
    expect(source, contains('dragOffset: _activeCardDragOffset'));
    expect(source, contains('onPointerDown: _handlePointerDown'));
    expect(source, isNot(contains('onLongPressStart')));
    expect(source, contains('child: RepaintBoundary('));
    expect(source, contains('Matrix4.translationValues(dx, 0, 0)'));
    expect(source, contains('dragOffset.dx * 0.62'));
    expect(source, contains('dragOffset.dy * 0.28'));
    expect(source, isNot(contains('dx + dragOffset.dx')));
  });

  test('沉浸封面堆叠使用完整播放队列且最多绘制五张', () {
    final stageSource =
        File(
          'lib/features/music/presentation/player/music_immersive_player_stage.dart',
        ).readAsStringSync();
    final deckSource =
        File(
          'lib/features/music/presentation/player/music_immersive_cover_deck.dart',
        ).readAsStringSync();

    expect(stageSource, contains('state?.playbackQueue'));
    expect(stageSource, isNot(contains('.take(12)')));
    expect(stageSource, isNot(contains('_syncedTrackId')));
    expect(stageSource, contains('index < 0 || _deckIndex == index'));
    expect(stageSource, contains('_selectDeckTrack(tracks, nextIndex)'));
    expect(deckSource, contains('_deckPaintOrder = <int>[4, 3, 2, 1]'));
  });

  testWidgets('桌面长按拖拽只移动顶层封面并切换歌曲', (tester) async {
    int? selectedIndex;
    const tracks = <MusicTrack>[
      MusicTrack(
        id: 'track-1',
        fileNodeId: 'file-1',
        title: 'Track 1',
        artistName: 'Artist',
        albumTitle: 'Album',
        format: 'mp3',
        favorite: false,
      ),
      MusicTrack(
        id: 'track-2',
        fileNodeId: 'file-2',
        title: 'Track 2',
        artistName: 'Artist',
        albumTitle: 'Album',
        format: 'mp3',
        favorite: false,
      ),
      MusicTrack(
        id: 'track-3',
        fileNodeId: 'file-3',
        title: 'Track 3',
        artistName: 'Artist',
        albumTitle: 'Album',
        format: 'mp3',
        favorite: false,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 700,
              child: MusicImmersiveCoverDeck(
                palette: MusicImmersivePalette.digital,
                tracks: tracks,
                selectedIndex: 0,
                currentTrack: tracks.first,
                expanded: true,
                scale: 1,
                onSelected: (index) => selectedIndex = index,
                onStep: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    final activeCard = find.byKey(const ValueKey('track-1-drag-surface-0'));
    final rearCard = find.byKey(const ValueKey('track-2-drag-surface-1'));
    final activeBefore = tester.getCenter(activeCard);
    final gesture = await tester.startGesture(
      activeBefore,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await tester.pump();
    final pressFeedback =
        find
            .ancestor(of: activeCard, matching: find.byType(AnimatedScale))
            .first;
    expect(tester.widget<AnimatedScale>(pressFeedback).scale, 0.965);
    await gesture.moveBy(const Offset(-100, 0));
    await tester.pump();

    final activeTransform =
        tester.widget<AnimatedContainer>(activeCard).transform!;
    final rearTransform = tester.widget<AnimatedContainer>(rearCard).transform!;
    expect(activeTransform.getTranslation().x, closeTo(-62, 0.01));
    expect(rearTransform.getTranslation().x, 0);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(pressFeedback).scale, 1);
    expect(selectedIndex, 1);
  });
}
