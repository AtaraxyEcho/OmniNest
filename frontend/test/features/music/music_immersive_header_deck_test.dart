import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_visualizer_preset.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_layout_spec.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_player.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_style.dart';

void main() {
  test('沉浸全屏走手动全屏入口，页面不再绑定 F11 作用域', () {
    final musicSource = _readFlat(
      'lib/features/music/presentation/player/music_immersive_overlay.dart',
    );
    final portalSource = _readFlat(
      'lib/features/portal/presentation/widgets/portal_desktop_visual_shells.dart',
    );

    expect(musicSource, _flatLacks('AppFullscreenShortcutScope'));
    expect(musicSource, _flatContains('AppFullscreenButton'));
    expect(musicSource, _flatContains('reservedTopInset: safeTop + 58'));
    // F11 由 app.dart 全局处理器统一分发为无边框全屏；任何页面级 F11 绑定
    // 都会与全局处理器同一按键双重触发（硬件层与焦点树无条件先后执行）。
    expect(portalSource, _flatLacks('AppFullscreenShortcutScope'));
    expect(portalSource, _flatContains('AppFullscreenButton'));
    expect(portalSource, _flatLacks('_PortalImmersiveButton'));
  });

  test('沉浸封面卡片滑动循环导航不截断', () {
    final source = _readFlat(
      'lib/features/music/presentation/player/music_immersive_player_stage.dart',
    );

    // 末端/队首回绕用取模实现，禁止 clamp 截断。
    expect(source, _flatLacks('clamp(0, tracks.length - 1)'));
    expect(source, _flatContains('(_deckIndex + delta) % tracks.length'));
  });

  test('沉浸顶部只显示放大的歌曲信息与收藏按钮', () {
    final source = _readFlat(
      'lib/features/music/presentation/player/music_immersive_track_header.dart',
    );
    final spec = _readFlat(
      'lib/features/music/presentation/player/music_immersive_layout_spec.dart',
    );

    // 顶部只承载歌曲信息与收藏入口：不渲染封面、不承载播放控制。
    expect(source, _flatLacks('_MusicImmersiveArtwork'));
    expect(source, _flatLacks('onTogglePlayback'));
    // 编辑视觉按钮左侧的收藏按钮已按需求删除，顶栏不再有收藏入口。
    expect(source, _flatLacks('onToggleFavorite'));
    expect(source, _flatLacks('_buildFavoriteButton'));
    expect(source, _flatLacks('favorite_rounded'));
    // 字号公式集中在规格文件；顶栏只消费它，并强制 strut 行高，避免字体自身
    // 行高比设置值大而让行盒撑破顶栏块。
    expect(spec, _flatContains('(27 * scale).clamp(23.0, 34.0)'));
    expect(spec, _flatContains('(16 * scale).clamp(14.0, 19.0)'));
    expect(source, _flatContains('musicHeaderTitleSize(scale)'));
    expect(source, _flatContains('musicHeaderSubtitleSize(scale)'));
    expect(source, _flatContains('forceStrutHeight: true'));
  });

  test('沉浸右侧封面卡片保持不透明', () {
    final source = _readFlat(
      'lib/features/music/presentation/player/music_immersive_cover_deck.dart',
    );

    expect(source, _flatLacks('AnimatedOpacity'));
    expect(source, _flatLacks('final opacity ='));
    expect(source, _flatContains('palette.surfaceStrong.withValues('));
    expect(source, _flatContains('alpha: 1'));
  });

  test('沉浸右侧封面卡片使用独立指针跟踪', () {
    final source = _readFlat(
      'lib/features/music/presentation/player/music_immersive_cover_deck.dart',
    );

    expect(source, _flatContains('_dragPointer'));
    expect(source, _flatContains('_handlePointerMove'));
    expect(source, _flatContains('SystemMouseCursors.grabbing'));
    expect(source, _flatContains('_dominantDrag'));
    expect(source, _flatContains('_resolveDragDelta'));
    expect(source, _flatContains('_deckPaintOrder = <int>[4, 3, 2, 1]'));
    expect(source, _flatContains('_buildActiveDeckCard()'));
    expect(source, _flatContains('dragOffset: _activeCardDragOffset'));
    expect(source, _flatContains('onPointerDown: _handlePointerDown'));
    expect(source, _flatLacks('onLongPressStart'));
    expect(source, _flatContains('child: RepaintBoundary('));
    // 拖拽反馈是挂在卡面最内层的纯平移：档位变换与拖拽位移互不污染。
    expect(source, _flatContains('resolveMusicDeckCard(layout, slot)'));
    expect(source, _flatContains('dragOffset.dx * 0.62'));
    expect(source, _flatContains('dragOffset.dy * 0.28'));
    expect(source, _flatLacks('dx + dragOffset.dx'));
  });

  test('沉浸封面堆叠使用完整播放队列且最多绘制五张', () {
    final stageSource = _readFlat(
      'lib/features/music/presentation/player/music_immersive_player_stage.dart',
    );
    final deckSource = _readFlat(
      'lib/features/music/presentation/player/music_immersive_cover_deck.dart',
    );

    expect(stageSource, _flatContains('state?.playbackQueue'));
    expect(stageSource, _flatLacks('.take(12)'));
    expect(stageSource, _flatLacks('_syncedTrackId'));
    expect(stageSource, _flatContains('index < 0 || _deckIndex == index'));
    expect(stageSource, _flatContains('_selectDeckTrack(tracks, nextIndex)'));
    expect(deckSource, _flatContains('_deckPaintOrder = <int>[4, 3, 2, 1]'));
  });

  testWidgets('卡组悬停不触发 MouseTracker 设备更新重入', (tester) async {
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
              width: 460,
              height: 400,
              child: MusicImmersiveCoverDeck(
                palette: MusicImmersivePalette.digital,
                tracks: tracks,
                selectedIndex: 0,
                currentTrack: tracks.first,
                expanded: false,
                scale: 1,
                layout: PortalMusicLayout.left,
                isPlaying: true,
                stageSize: const Size(440, 385),
                onSelected: (_) {},
                onStep: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 用真实鼠标悬停事件扫过在读卡、露出带与空白处，覆盖 enter/exit 交错。
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    const path = <Offset>[
      Offset(120, 200),
      Offset(200, 210),
      Offset(300, 220),
      Offset(360, 200),
      Offset(120, 200),
      Offset(20, 20),
    ];
    for (final position in path) {
      final hit = HitTestResult();
      tester.binding.hitTestInView(hit, position, tester.view.viewId);
      tester.binding.dispatchEvent(pointer.hover(position), hit);
      await tester.pump();
    }
    // 悬停后在读卡的变换会变化，再推进一帧确认布局收敛。
    await tester.pump();
  });

  testWidgets('悬停在读卡放大封面，悬停后卡命中条触发拉出反馈', (tester) async {
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
              width: 460,
              height: 400,
              child: MusicImmersiveCoverDeck(
                palette: MusicImmersivePalette.digital,
                tracks: tracks,
                selectedIndex: 0,
                currentTrack: tracks.first,
                expanded: false,
                scale: 1,
                layout: PortalMusicLayout.left,
                // 暂停态：均衡器不持续动画，pumpAndSettle 才能收敛。
                isPlaying: false,
                stageSize: const Size(440, 385),
                onSelected: (_) {},
                onStep: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    HitTestResult hitAt(Offset position) {
      final hit = HitTestResult();
      tester.binding.hitTestInView(hit, position, tester.view.viewId);
      return hit;
    }

    // 在读卡中心悬停：样例封面的 group-hover:scale-105。
    final activeCard = find.byKey(const ValueKey('track-1-drag-surface-0'));
    tester.binding.dispatchEvent(
      pointer.hover(tester.getCenter(activeCard)),
      hitAt(tester.getCenter(activeCard)),
    );
    await tester.pumpAndSettle();
    final deckScales = tester.widgetList<AnimatedScale>(
      find.descendant(
        of: find.byType(MusicImmersiveCoverDeck),
        matching: find.byType(AnimatedScale),
      ),
    );
    expect(
      deckScales.any((widget) => (widget.scale - 1.05).abs() < 1e-9),
      isTrue,
    );

    // 命中条悬停：后卡按样例位移拉出（slot 1 常态 34px → 悬停 60px）。
    final rearCard = find.byKey(const ValueKey('track-2-drag-surface-1'));
    final rearBefore =
        tester
            .widget<AnimatedContainer>(
              find
                  .ancestor(
                    of: rearCard,
                    matching: find.byType(AnimatedContainer),
                  )
                  .first,
            )
            .transform!
            .getTranslation()
            .x;
    final strip = find.byKey(const ValueKey('deck-hit-strip-1'));
    tester.binding.dispatchEvent(
      pointer.hover(tester.getCenter(strip)),
      hitAt(tester.getCenter(strip)),
    );
    await tester.pumpAndSettle();
    final rearAfter =
        tester
            .widget<AnimatedContainer>(
              find
                  .ancestor(
                    of: rearCard,
                    matching: find.byType(AnimatedContainer),
                  )
                  .first,
            )
            .transform!
            .getTranslation()
            .x;
    expect(rearAfter, closeTo(kMusicIsometricHoverOffsets[1].dx, 0.5));
    expect(rearAfter, isNot(closeTo(rearBefore, 0.5)));
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
                layout: PortalMusicLayout.left,
                isPlaying: false,
                stageSize: const Size(440, 385),
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

/// 源码断言对排版的处理。
///
/// `dart format` 会按页宽折行，并在折行后的实参表尾部保留尾随逗号，断言若按源码
/// 原文匹配，会被一次格式化无声破坏（单行调用被拆成多行、多出尾随逗号）。因此
/// 比较前统一去掉全部空白并消除尾随逗号，使断言只依赖标识符、字面量与实参序列，
/// 而不依赖当时的排版。
String _normalizeForMatch(String value) {
  return value.replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r',\)'), ')');
}

/// 读取源码并归一化排版，与 [_flatContains] / [_flatLacks] 配套使用。
String _readFlat(String path) {
  return _normalizeForMatch(File(path).readAsStringSync());
}

/// 排版无关的包含断言。
Matcher _flatContains(String needle) {
  return contains(_normalizeForMatch(needle));
}

/// 排版无关的排除断言。
Matcher _flatLacks(String needle) {
  return isNot(_flatContains(needle));
}
