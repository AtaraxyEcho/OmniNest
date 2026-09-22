import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/features/music/application/music_audio_playback.dart';
import 'package:omninest/features/music/application/music_spectrum_frame.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_visualizer_preset.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_layout_spec.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_lyrics.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_style.dart';

/// 滚动歌词形态：连续列表呈现全部歌词、当前行居中跟随、手动滚动暂停跟随
/// 后恢复、点击行 seek、顶底渐隐、已读/未读两色（纯色或上下渐变）与逐字
/// 填充。三端共用同一组件，因此本组测试即三端一致性的行为基线。

/// 推进若干帧：post-frame 中启动的跟随动画首帧不产生位移，
/// 需要额外帧完成（真实运行时按 60fps 连续推进）。
Future<void> _advance(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  testWidgets('滚动模式呈现连续列表并跟随当前行居中', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(_lyricsApp(player: player));
    await _advance(tester);

    expect(find.byType(ListView), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .data,
      'Lyric 10',
    );

    // 播放推进后当前行前移，列表偏移随之变化（居中跟随）。
    final before =
        tester.widget<ListView>(find.byType(ListView)).controller!.offset;
    player.emit(const Duration(seconds: 18));
    await _advance(tester);
    final after =
        tester.widget<ListView>(find.byType(ListView)).controller!.offset;

    expect(after, greaterThan(before));
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .data,
      'Lyric 18',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击歌词行跳转到该行时间点', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 5),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(_lyricsApp(player: player));
    await _advance(tester);

    // 点击视口内的邻近行（初始居中于第 5 行，视口约 4 行高）。
    await tester.tap(find.text('Lyric 6'));
    await _advance(tester);

    // seek 会经 fake 播放器回发位置事件。
    expect(player.state.position, const Duration(seconds: 6));
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .data,
      'Lyric 6',
    );
  });

  testWidgets('拖动列表暂停跟随并在松手后跳转到焦点行', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(_lyricsApp(player: player));
    await _advance(tester);

    // 拖动：跟随即暂停，拖动期间列表不被拉回当前行。
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ListView)),
    );
    await tester.pump();
    // 分两次移动：第一次越过触摸 slop 让滚动开始，第二次继续拖动。
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -180));
    await tester.pump();
    final draggedOffset =
        tester.widget<ListView>(find.byType(ListView)).controller!.offset;
    expect(draggedOffset, greaterThan(0));
    expect(find.text('回到当前播放'), findsOneWidget);

    player.emit(const Duration(seconds: 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<ListView>(find.byType(ListView)).controller!.offset,
      draggedOffset,
      reason: '拖动期间播放推进不得回拉列表',
    );

    // 松手：跳转到焦点位命中的歌词行，并恢复跟随。
    await gesture.up();
    await _advance(tester);
    expect(player.state.position, isNot(const Duration(seconds: 20)));
    expect(find.text('回到当前播放'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手动滚动后点击"回到当前播放"恢复跟随', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(_lyricsApp(player: player));
    await _advance(tester);

    // 滚轮滚动只暂停跟随（不跳转），并浮出回到当前按钮。
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.byType(ListView))),
    );
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 300)));
    await tester.pump();
    final wheelOffset =
        tester.widget<ListView>(find.byType(ListView)).controller!.offset;
    expect(find.text('回到当前播放'), findsOneWidget);

    // 点击按钮：恢复跟随并把当前行滚回焦点位，按钮消失。
    await tester.tap(find.text('回到当前播放'));
    await _advance(tester);
    expect(find.text('回到当前播放'), findsNothing);
    expect(
      tester.widget<ListView>(find.byType(ListView)).controller!.offset,
      isNot(wheelOffset),
    );
  });

  testWidgets('滚轮滚动同样暂停跟随，不被立即回拉', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(_lyricsApp(player: player));
    await _advance(tester);

    // 滚轮滚动：pointerScroll 会派发非 idle 的 UserScrollNotification，
    // 过去只认 dragDetails，导致滚轮滚动被跟随动画立即拉回。
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(find.byType(ListView))),
    );
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 300)));
    await tester.pump();
    final wheelOffset =
        tester.widget<ListView>(find.byType(ListView)).controller!.offset;

    // 播放推进期间列表不得被拉回当前行。
    player.emit(const Duration(seconds: 24));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<ListView>(find.byType(ListView)).controller!.offset,
      wheelOffset,
      reason: '滚轮滚动后应暂停跟随，播放推进不得回拉列表',
    );
  });

  testWidgets('滚动模式行距不受"行数"设置影响', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(
      _lyricsApp(
        player: player,
        settings: PortalLyricVisualSettings.defaults.copyWith(visibleLines: 1),
      ),
    );
    await _advance(tester);
    final oneLineSlot =
        tester
            .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
            .style!
            .fontSize!;

    await tester.pumpWidget(
      _lyricsApp(
        player: player,
        settings: PortalLyricVisualSettings.defaults.copyWith(visibleLines: 9),
      ),
    );
    await _advance(tester);
    final nineLineSlot =
        tester
            .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
            .style!
            .fontSize!;

    // 行数只属于多行歌词形态：滚动模式下改行数不得改变行高/字号。
    expect(nineLineSlot, oneLineSlot);
  });

  testWidgets('歌词位置决定文字块锚点与文本排列（居中/居左/居右）', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 1),
    );
    addTearDown(player.dispose);
    const short = '短句';
    const long = '这一句明显更长的歌词用来验证对齐方式是否真的贴住了边缘';
    const lines = <MusicLyricLine>[
      MusicLyricLine(position: Duration.zero, text: short),
      MusicLyricLine(position: Duration(seconds: 1), text: long),
      MusicLyricLine(position: Duration(seconds: 2), text: short),
    ];
    Rect column() => tester.getRect(find.byType(ListView));

    // 居中锚点：块居中、块内文本按宿主排列（桌面端居左），长短行共享块左边缘。
    await tester.pumpWidget(
      _lyricsApp(player: player, textAlign: TextAlign.left, lyrics: lines),
    );
    await _advance(tester);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .textAlign,
      TextAlign.left,
    );
    expect(tester.getCenter(find.text(long)).dx, column().center.dx);
    expect(
      tester.getTopLeft(find.text(short).first).dx,
      tester.getTopLeft(find.text(long)).dx,
    );
    expect(
      tester.getSize(find.text(short).first).width,
      tester.getSize(find.text(long)).width,
    );

    // 居左锚点：文字块贴住歌词列左边缘，文本左对齐。
    await tester.pumpWidget(
      _lyricsApp(
        player: player,
        textAlign: TextAlign.left,
        blockAnchor: Alignment.centerLeft,
        lyrics: lines,
      ),
    );
    await _advance(tester);
    expect(tester.getTopLeft(find.text(long)).dx, column().left);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .textAlign,
      TextAlign.left,
    );

    // 居右锚点：文字块贴住歌词列右边缘，文本右对齐，长短行共享块右边缘。
    await tester.pumpWidget(
      _lyricsApp(
        player: player,
        textAlign: TextAlign.left,
        blockAnchor: Alignment.centerRight,
        lyrics: lines,
      ),
    );
    await _advance(tester);
    expect(tester.getTopRight(find.text(long)).dx, column().right);
    expect(
      tester.getTopRight(find.text(short).first).dx,
      tester.getTopRight(find.text(long)).dx,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .textAlign,
      TextAlign.right,
    );

    // 多行歌词形态忽略宿主的排列，一律文本居中（固定窗口没有列表）。
    await tester.pumpWidget(
      _lyricsApp(
        player: player,
        textAlign: TextAlign.left,
        scrollMode: false,
        lyrics: lines,
      ),
    );
    await _advance(tester);
    expect(tester.widget<Text>(find.text(long)).textAlign, TextAlign.center);
    final box = tester.getRect(find.byType(MusicImmersiveLyrics));
    expect(tester.getCenter(find.text(long)).dx, box.center.dx);
  });

  testWidgets('歌词区上下边缘做渐隐处理，避免被顶栏底栏硬切', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(_lyricsApp(player: player));
    await _advance(tester);

    final fade = tester.widget<ShaderMask>(
      find.byKey(const ValueKey('music-lyric-edge-fade')),
    );
    // dstIn：遮罩两端透明，歌词行在上下边缘逐步淡出。
    expect(fade.blendMode, BlendMode.dstIn);
  });

  testWidgets('行距设置只改变相邻行之间的空隙', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);

    Future<double> gapFor(double lineSpacing) async {
      await tester.pumpWidget(
        _lyricsApp(
          player: player,
          settings: PortalLyricVisualSettings.defaults.copyWith(
            lineSpacing: lineSpacing,
          ),
        ),
      );
      await _advance(tester);
      // 取两行相邻的非当前行：其中心距即行槽高度，不受焦点行字号影响。
      final upper = tester.getCenter(find.text('Lyric 9')).dy;
      final lower = tester.getCenter(find.text('Lyric 8')).dy;
      return (upper - lower).abs();
    }

    final narrow = await gapFor(0.75);
    final wide = await gapFor(1.65);
    expect(wide, greaterThan(narrow));
    expect(tester.takeException(), isNull);
  });

  testWidgets('在读色与非当前句色各自支持纯色或上下渐变', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);

    await tester.pumpWidget(
      _lyricsApp(
        player: player,
        settings: PortalLyricVisualSettings.defaults.copyWith(
          currentPaint: const LyricPaint.vertical(0xFFFF0000, 0xFF0000FF),
          inactivePaint: const LyricPaint.solid(0xFF00FF00),
        ),
      ),
    );
    await _advance(tester);

    // 在读色为上下渐变：读行经逐字填充管线渲染，渐变由双层画法的
    // 竖向遮罩保留（文字本体为不透明白）。
    expect(
      find.byKey(const ValueKey('music-lyric-word-fill-layered')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .style!
          .color,
      Colors.white,
    );

    // 非当前句色为纯色：已唱行与未唱行都用同一色，按非当前句透明度压暗。
    final pastStyle = tester.widget<Text>(find.text('Lyric 9')).style!;
    final upcomingStyle = tester.widget<Text>(find.text('Lyric 11')).style!;
    final expectedInactive = const Color(
      0xFF00FF00,
    ).withValues(alpha: PortalLyricVisualSettings.defaults.inactiveOpacity);
    expect(pastStyle.color, expectedInactive);
    expect(upcomingStyle.color, expectedInactive);
    expect(tester.takeException(), isNull);
  });

  testWidgets('默认两色为主流方案：在读白、其余半透明白', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(
      _lyricsApp(
        player: player,
        settings: PortalLyricVisualSettings.defaults.copyWith(),
      ),
    );
    await _advance(tester);

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .style!
          .color,
      const Color(0xFFFFFFFF),
    );
    expect(
      tester.widget<Text>(find.text('Lyric 9')).style!.color,
      const Color(0xFFFFFFFF).withValues(alpha: 0.5),
    );
    expect(PortalLyricVisualSettings.defaults.inactiveOpacity, 0.5);
  });

  testWidgets('原文与译文各自独立使用上下渐变', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 3),
    );
    addTearDown(player.dispose);
    const lyrics = <MusicLyricLine>[
      MusicLyricLine(
        position: Duration(seconds: 3),
        text: 'Hello world',
        translation: '你好世界',
      ),
    ];

    await tester.pumpWidget(
      _lyricsApp(
        player: player,
        lyrics: lyrics,
        settings: PortalLyricVisualSettings.defaults.copyWith(
          currentPaint: const LyricPaint.vertical(0xFFFF0000, 0xFF0000FF),
        ),
      ),
    );
    await tester.pump();

    // 双层填充画法会叠加未唱层与读色层，文本各出现两次。
    expect(find.text('Hello world'), findsNWidgets(2));
    expect(find.text('你好世界'), findsNWidgets(2));
    // 原文与译文各自一个渐变遮罩（读行经逐字填充的双层画法各自套竖向渐变）：
    // 共用会让译文整行落在渐变下半段。
    expect(
      find.byKey(const ValueKey('music-lyric-word-fill-layered')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('music-lyric-translation-word-fill-layered')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('歌词延迟校准把行切换整体后移', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(milliseconds: 3400),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(_lyricsApp(player: player));
    await _advance(tester);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .data,
      'Lyric 3',
    );

    await tester.pumpWidget(
      _lyricsApp(
        player: player,
        settings: PortalLyricVisualSettings.defaults.copyWith(offsetMs: 500),
      ),
    );
    await _advance(tester);
    // 有效位置回退到 2.9s：当前行回到第 2 句。
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .data,
      'Lyric 2',
    );
  });

  testWidgets('焦点行锚点决定当前行在视口中的位置', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);

    Future<double> anchorFraction(double anchor) async {
      await tester.pumpWidget(
        _lyricsApp(
          player: player,
          settings: PortalLyricVisualSettings.defaults.copyWith(
            focusAnchor: anchor,
          ),
        ),
      );
      await _advance(tester);
      final box = tester.getRect(find.byType(ListView));
      final active = tester.getCenter(
        find.byKey(const ValueKey('music-lyric-active')),
      );
      return (active.dy - box.top) / box.height;
    }

    expect(await anchorFraction(0.5), closeTo(0.5, 0.02));
    expect(await anchorFraction(0.4), closeTo(0.4, 0.02));
  });

  testWidgets('字号以 px 生效，滚动形态在读行与其余行同号', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);

    Future<(double, double)> fontsFor(int fontSizePx) async {
      await tester.pumpWidget(
        _lyricsApp(
          player: player,
          settings: PortalLyricVisualSettings.defaults.copyWith(
            fontSizePx: fontSizePx,
          ),
        ),
      );
      await _advance(tester);
      return (
        tester
            .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
            .style!
            .fontSize!,
        tester.widget<Text>(find.text('Lyric 9')).style!.fontSize!,
      );
    }

    final (activeDefault, inactiveDefault) = await fontsFor(18);
    // px 即最终字号：不被设备缩放放大；滚动形态在读行与其余行同号。
    expect(inactiveDefault, 18);
    expect(activeDefault, inactiveDefault);

    final (activeLarge, inactiveLarge) = await fontsFor(24);
    expect(inactiveLarge, 24);
    expect(activeLarge, inactiveLarge);
  });

  testWidgets('译文开关关闭时不渲染译文行且行槽预留减少', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);
    final translated = List<MusicLyricLine>.generate(
      30,
      (index) => MusicLyricLine(
        position: Duration(seconds: index),
        text: 'Lyric $index',
        translation: '译文 $index',
      ),
    );

    Future<double> slotGapFor(bool translationEnabled) async {
      await tester.pumpWidget(
        _lyricsApp(
          player: player,
          lyrics: translated,
          settings: PortalLyricVisualSettings.defaults.copyWith(
            translationEnabled: translationEnabled,
          ),
        ),
      );
      await _advance(tester);
      final upper = tester.getCenter(find.text('Lyric 9')).dy;
      final lower = tester.getCenter(find.text('Lyric 8')).dy;
      return (upper - lower).abs();
    }

    final withTranslation = await slotGapFor(true);
    expect(find.text('译文 10'), findsOneWidget);
    final withoutTranslation = await slotGapFor(false);
    // 关闭后译文行不渲染，行槽不再为译文预留高度。
    expect(find.text('译文 10'), findsNothing);
    expect(withoutTranslation, lessThan(withTranslation));
    expect(tester.takeException(), isNull);
  });

  testWidgets('曲目级歌词延迟覆盖优先于全局校准', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(milliseconds: 3400),
    );
    addTearDown(player.dispose);
    // 无覆盖时 3.4s 落在第 3 行。
    await tester.pumpWidget(_lyricsApp(player: player));
    await _advance(tester);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .data,
      'Lyric 3',
    );

    // 曲目级覆盖 500ms：有效位置回退到 2.9s，当前行回到第 2 行。
    await tester.pumpWidget(_lyricsApp(player: player, trackOffsetMs: 500));
    await _advance(tester);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .data,
      'Lyric 2',
    );

    // 曲目级覆盖优先：全局校准 -200ms 不影响覆盖生效。
    await tester.pumpWidget(
      _lyricsApp(
        player: player,
        trackOffsetMs: 500,
        settings: PortalLyricVisualSettings.defaults.copyWith(offsetMs: -200),
      ),
    );
    await _advance(tester);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .data,
      'Lyric 2',
    );
  });

  testWidgets('长按行菜单提供复制歌词与延迟微调', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);
    final adjustments = <int>[];
    await tester.pumpWidget(
      _lyricsApp(player: player, onAdjustLyricOffset: adjustments.add),
    );
    await _advance(tester);

    await tester.longPress(find.text('Lyric 10'));
    await tester.pumpAndSettle();

    expect(find.text('复制歌词'), findsOneWidget);
    expect(find.text('歌词延后 0.1 秒'), findsOneWidget);
    expect(find.text('歌词提前 0.1 秒'), findsOneWidget);

    await tester.tap(find.text('歌词延后 0.1 秒'));
    await tester.pumpAndSettle();
    expect(adjustments, [100]);

    await tester.longPress(find.text('Lyric 10'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('歌词提前 0.1 秒'));
    await tester.pumpAndSettle();
    expect(adjustments, [100, -100]);
  });

  testWidgets('逐字填充按已完成词时长推进（纯色单层遮罩）', (tester) async {
    // 行 3.0s–4.0s，词级仅覆盖前 0.4s：位置 3.2s 的填充比例 = 0.2/0.4 = 50%
    //（曲线见 music_models_test 的 fillProgressAt 断言，非线性 20%）。
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 3),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(_lyricsApp(player: player, wordTimeline: true));
    await _advance(tester);

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .data,
      'Lyric 3',
    );
    player.emit(const Duration(milliseconds: 3200));
    await tester.pump();

    // 纯色组合走单层横向遮罩分支：srcIn 用遮罩色替换文字色实现左右分段。
    final singleMask = tester.widget<ShaderMask>(
      find.byKey(const ValueKey('music-lyric-word-fill')),
    );
    expect(singleMask.blendMode, BlendMode.srcIn);
    expect(
      find.byKey(const ValueKey('music-lyric-word-fill-layered')),
      findsNothing,
    );
  });

  testWidgets('逐字填充开关关闭后即使有词级数据也不填充', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 3),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(
      _lyricsApp(
        player: player,
        wordTimeline: true,
        settings: PortalLyricVisualSettings.defaults.copyWith(
          wordFillEnabled: false,
        ),
      ),
    );
    await _advance(tester);
    player.emit(const Duration(milliseconds: 3200));
    await tester.pump();

    expect(find.byKey(const ValueKey('music-lyric-word-fill')), findsNothing);
    expect(
      find.byKey(const ValueKey('music-lyric-word-fill-layered')),
      findsNothing,
    );
    // 在读行整行用读色，不受开关影响。
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .data,
      'Lyric 3',
    );
  });

  testWidgets('无词级数据的行按行时长估算填充，暂停后填充隐藏', (tester) async {
    // 无词级数据：按行时长线性估算填充（3.21s 落在第 4 行 0-1s 的 21% 处）。
    final plainPlayer = _FakeMusicAudioPlayback(
      initialPosition: const Duration(milliseconds: 3200),
    );
    addTearDown(plainPlayer.dispose);
    await tester.pumpWidget(_lyricsApp(player: plainPlayer));
    await _advance(tester);
    plainPlayer.emit(const Duration(milliseconds: 3210));
    await tester.pump();
    expect(find.byKey(const ValueKey('music-lyric-word-fill')), findsOneWidget);

    // 有词级数据但暂停：填充遮罩隐藏，在读行整行用读色。
    final pausedPlayer = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 3),
    );
    addTearDown(pausedPlayer.dispose);
    await tester.pumpWidget(
      _lyricsApp(player: pausedPlayer, wordTimeline: true),
    );
    await _advance(tester);
    pausedPlayer.emit(const Duration(milliseconds: 3200));
    await tester.pump();
    expect(find.byKey(const ValueKey('music-lyric-word-fill')), findsOneWidget);
    await pausedPlayer.pause();
    pausedPlayer.emit(const Duration(milliseconds: 3300));
    await tester.pump();
    expect(find.byKey(const ValueKey('music-lyric-word-fill')), findsNothing);
  });

  testWidgets('填充与上下渐变共存：双层叠加各自保留渐变', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 3),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(
      _lyricsApp(
        player: player,
        wordTimeline: true,
        settings: PortalLyricVisualSettings.defaults.copyWith(
          currentPaint: const LyricPaint.vertical(0xFFFF0000, 0xFF0000FF),
        ),
      ),
    );
    await _advance(tester);
    player.emit(const Duration(milliseconds: 3200));
    await tester.pump();

    // 双层模式：外层横向遮罩只做 alpha 裁切（dstIn）——若误用 srcIn，已唱
    // 部分会被替换成遮罩色，竖向渐变色丢失，视觉上等于没有填充。
    final mask = tester.widget<ShaderMask>(
      find.byKey(const ValueKey('music-lyric-word-fill-layered')),
    );
    expect(mask.blendMode, BlendMode.dstIn);
    // 在读行文本本身仍然存在（底层非当前句色整行 + 顶层读色）。
    expect(find.byKey(const ValueKey('music-lyric-active')), findsOneWidget);
  });

  testWidgets('居左/居中/居右锚点下填充遮罩都按当前行挂载', (tester) async {
    final player = _FakeMusicAudioPlayback(
      initialPosition: const Duration(seconds: 3),
    );
    addTearDown(player.dispose);

    Future<bool> fillPresentFor(Alignment anchor) async {
      await tester.pumpWidget(
        _lyricsApp(player: player, wordTimeline: true, blockAnchor: anchor),
      );
      await tester.pump();
      player.emit(const Duration(milliseconds: 3200));
      await tester.pump();
      return find
          .byKey(const ValueKey('music-lyric-word-fill'))
          .evaluate()
          .isNotEmpty;
    }

    // 遮罩作用于该行文本盒，三种锚点下填充比例一致（曲线已由领域测试锚定）。
    expect(await fillPresentFor(Alignment.centerLeft), isTrue);
    expect(await fillPresentFor(Alignment.center), isTrue);
    expect(await fillPresentFor(Alignment.centerRight), isTrue);
  });

  test('在读/非当前句两色画法参与视觉设置序列化往返（滚动形态不在其中）', () {
    final json =
        PortalLyricVisualSettings.defaults
            .copyWith(
              currentPaint: const LyricPaint.vertical(0xFF123456, 0xFF654321),
              inactivePaint: const LyricPaint.solid(0xFFAABBCC),
            )
            .toJson();

    // 歌词形态属设备级偏好，不进入跨端同步的视觉设置。
    expect(json.containsKey('scrollMode'), isFalse);
    final restored = PortalLyricVisualSettings.fromJson(json);
    expect(restored.currentPaint.mode, LyricPaintMode.verticalGradient);
    expect(restored.currentPaint.colors, <int>[0xFF123456, 0xFF654321]);
    expect(restored.inactivePaint.mode, LyricPaintMode.solid);
    expect(restored.inactivePaint.primary, 0xFFAABBCC);

    // v6 的 readPaint/unreadPaint 键继续可读（旧客户端已写入的数据）。
    final v6 = PortalLyricVisualSettings.fromJson(const <String, dynamic>{
      'readPaint': <String, dynamic>{
        'mode': 'verticalGradient',
        'colors': <int>[0xFF010203, 0xFF040506],
      },
      'unreadPaint': <String, dynamic>{
        'mode': 'solid',
        'colors': <int>[0xFF0A0B0C],
      },
    });
    expect(v6.currentPaint.colors, <int>[0xFF010203, 0xFF040506]);
    expect(v6.inactivePaint.primary, 0xFF0A0B0C);

    // 更早的三色 + 渐变开关 + 溢光数据迁移到两色画法，溢光字段被忽略。
    final legacy = PortalLyricVisualSettings.fromJson(const <String, dynamic>{
      'enabled': true,
      'activeColorValue': 0xFF112233,
      'unreadColorValue': 0xFF778899,
      'gradientEnabled': true,
      'gradientTopColorValue': 0xFF112233,
      'gradientBottomColorValue': 0xFF445566,
      'shadowEnabled': true,
      'glowIntensity': 1.6,
      'glowColorValue': 0xFF4AD5FF,
    });
    expect(legacy.currentPaint.mode, LyricPaintMode.verticalGradient);
    expect(legacy.currentPaint.colors, <int>[0xFF112233, 0xFF445566]);
    expect(legacy.inactivePaint.primary, 0xFF778899);
    expect(legacy.toJson().containsKey('glowColorValue'), isFalse);
    expect(legacy.toJson().containsKey('shadowEnabled'), isFalse);

    // 逐字填充开关参与序列化：旧数据缺失该键时默认开启。
    final fillOff = PortalLyricVisualSettings.fromJson(
      PortalLyricVisualSettings.defaults
          .copyWith(wordFillEnabled: false)
          .toJson(),
    );
    expect(fillOff.wordFillEnabled, isFalse);
    expect(
      PortalLyricVisualSettings.fromJson(
        const <String, dynamic>{},
      ).wordFillEnabled,
      isTrue,
    );
  });

  testWidgets('复刻形态下用户双色覆盖样例常量', (tester) async {
    final player = _FakeMusicAudioPlayback(initialPosition: Duration.zero);
    addTearDown(player.dispose);
    final settings = PortalLyricVisualSettings.defaults.copyWith(
      currentPaint: const LyricPaint.solid(0xFFE7C86A),
      inactivePaint: const LyricPaint.solid(0xFF9AA7B8),
    );
    await tester.pumpWidget(
      _lyricsApp(
        player: player,
        settings: settings,
        spec: resolveMusicLyricSpec(PortalMusicLayout.left, 1),
      ),
    );
    await tester.pump();
    await tester.pump();

    // 在读行整行读用户色（距离档位为满亮）。
    final activeColor =
        tester
            .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
            .style
            ?.color;
    expect(activeColor, const Color(0xFFE7C86A));

    // 非在读行命中用户色并保留样例的距离压暗（相邻档 0.5）。
    final inactiveColor =
        tester.widget<Text>(find.text('Lyric 1')).style?.color;
    expect(inactiveColor!.toARGB32() & 0x00FFFFFF, 0x009AA7B8);
    expect(inactiveColor.a, lessThan(1));
  });

  testWidgets('复刻形态默认双色回落样例常量', (tester) async {
    final player = _FakeMusicAudioPlayback(initialPosition: Duration.zero);
    addTearDown(player.dispose);
    await tester.pumpWidget(
      _lyricsApp(
        player: player,
        settings: PortalLyricVisualSettings.defaults,
        spec: resolveMusicLyricSpec(PortalMusicLayout.left, 1),
      ),
    );
    await tester.pump();
    await tester.pump();

    final activeColor =
        tester
            .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
            .style
            ?.color;
    expect(activeColor, kMusicLyricActiveTextColor);
    // 非在读行回落样例正文色并带距离压暗。
    final inactiveColor =
        tester.widget<Text>(find.text('Lyric 1')).style?.color;
    expect(inactiveColor!.toARGB32() & 0x00FFFFFF, 0x00E2E2E6);
    expect(inactiveColor.a, lessThan(1));
  });

  testWidgets('复刻形态在读行上下渐变与逐字填充共存', (tester) async {
    final player = _FakeMusicAudioPlayback(initialPosition: Duration.zero);
    addTearDown(player.dispose);
    final settings = PortalLyricVisualSettings.defaults.copyWith(
      currentPaint: const LyricPaint.vertical(0xFFB7FFE7, 0xFF7098A0),
    );
    await tester.pumpWidget(
      _lyricsApp(
        player: player,
        settings: settings,
        wordTimeline: true,
        spec: resolveMusicLyricSpec(PortalMusicLayout.left, 1),
      ),
    );
    await tester.pump();
    await tester.pump();

    // 渐变在读色使填充进入双层叠加画法：底层非当前句色 + 顶层按边界裁切。
    expect(
      find.byKey(const ValueKey('music-lyric-word-fill-layered')),
      findsOneWidget,
    );
  });
}

Widget _lyricsApp({
  required _FakeMusicAudioPlayback player,
  PortalLyricVisualSettings? settings,
  bool scrollMode = true,
  TextAlign textAlign = TextAlign.left,
  Alignment blockAnchor = Alignment.center,
  double height = 400,
  List<MusicLyricLine>? lyrics,
  bool wordTimeline = false,
  int? trackOffsetMs,
  void Function(int deltaMs)? onAdjustLyricOffset,
  MusicLyricSpec? spec,
}) {
  final lines =
      lyrics ??
      List<MusicLyricLine>.generate(
        30,
        (index) => MusicLyricLine(
          position: Duration(seconds: index),
          text: 'Lyric $index',
        ),
      );
  final resolvedLines =
      wordTimeline
          ? List<MusicLyricLine>.generate(30, (index) {
            final base = lines[index];
            return MusicLyricLine(
              position: base.position,
              text: base.text,
              translation: base.translation,
              // 词级仅覆盖行首 0.4s：行远长于词级覆盖，验证按词时长推进。
              words: <MusicLyricWord>[
                MusicLyricWord(
                  offset: Duration.zero,
                  duration: const Duration(milliseconds: 400),
                  text: base.text,
                ),
              ],
            );
          })
          : lines;
  return MaterialApp(
    theme: ThemeData.dark(),
    // 歌词区包含本地化文案（"回到当前播放"），测试宿主需要提供委派，
    // 与真实宿主一致。
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: SizedBox(
        height: height,
        child: MusicImmersiveLyrics(
          palette: MusicImmersivePalette.digital,
          player: player,
          track: _track,
          lyrics: resolvedLines,
          scale: 1,
          lyricSettings: settings,
          lyricSpec: spec,
          trackOffsetMs: trackOffsetMs,
          onAdjustLyricOffset: onAdjustLyricOffset,
          // 滚动歌词形态、文本排列与块锚点由宿主传入（设备级偏好 + 端形态 + 歌词位置）。
          scrollMode: scrollMode,
          textAlign: textAlign,
          blockAnchor: blockAnchor,
          onTogglePlayback: () {},
          onPrevious: () {},
          onNext: () {},
        ),
      ),
    ),
  );
}

const MusicTrack _track = MusicTrack(
  id: 'track-1',
  fileNodeId: 'file-1',
  title: 'Track',
  artistName: 'Artist',
  albumTitle: 'Album',
  format: 'FLAC',
  favorite: false,
);

class _FakeMusicAudioPlayback implements MusicAudioPlayback {
  _FakeMusicAudioPlayback({required Duration initialPosition})
    : _state = MusicAudioPlayerState(
        playing: true,
        position: initialPosition,
        duration: const Duration(minutes: 3),
      );

  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast(sync: true);
  MusicAudioPlayerState _state;

  @override
  MusicAudioPlayerState get state => _state;

  @override
  ValueListenable<MusicSpectrumFrame> get spectrum =>
      const _SilentSpectrumListenable();

  @override
  late final MusicAudioPlayerStreams stream = MusicAudioPlayerStreams(
    position: _positionController.stream,
    duration: const Stream<Duration>.empty(),
    volume: const Stream<double>.empty(),
    completed: const Stream<bool>.empty(),
    log: const Stream<MusicAudioLog>.empty(),
  );

  void emit(Duration position) {
    _state = _state.copyWith(position: position);
    _positionController.add(position);
  }

  @override
  Future<void> openUrl(String url, {required bool play}) async {}

  @override
  Future<void> pause() async {
    _state = _state.copyWith(playing: false);
  }

  @override
  Future<void> play() async {
    _state = _state.copyWith(playing: true);
  }

  @override
  MusicSpectrumFrame? readSpectrumFrame({required MusicTrack track}) => null;

  @override
  Future<void> seek(Duration position) async {
    emit(position);
  }

  @override
  void setVolume(double volume) {
    _state = _state.copyWith(volume: volume);
  }

  @override
  void setRelativePlaySpeed(double speed) {}

  @override
  void setSpectrumTrack(MusicTrack? track) {}

  @override
  Future<void> dispose() async {
    await _positionController.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SilentSpectrumListenable implements ValueListenable<MusicSpectrumFrame> {
  const _SilentSpectrumListenable();

  @override
  MusicSpectrumFrame get value => MusicSpectrumFrame.silent();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
