import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_visualizer_preset.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_lyrics.dart';

import 'support/music_scroll_lyrics_harness.dart';

/// 滚动歌词形态：连续列表呈现全部歌词、当前行居中跟随、手动滚动暂停跟随
/// 后恢复、点击行 seek、顶底渐隐、已读/未读两色（纯色或上下渐变）与逐字
/// 填充。三端共用同一组件，因此本组测试即三端一致性的行为基线。

void main() {
  testWidgets('滚动模式呈现连续列表并跟随当前行居中', (tester) async {
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(musicScrollLyricsApp(player: player));
    await advanceFrames(tester);

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
    await advanceFrames(tester);
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
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 5),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(musicScrollLyricsApp(player: player));
    await advanceFrames(tester);

    // 点击视口内的邻近行（初始居中于第 5 行，视口约 4 行高）。
    await tester.tap(find.text('Lyric 6'));
    await advanceFrames(tester);

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
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(musicScrollLyricsApp(player: player));
    await advanceFrames(tester);

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
    await advanceFrames(tester);
    expect(player.state.position, isNot(const Duration(seconds: 20)));
    expect(find.text('回到当前播放'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手动滚动后点击"回到当前播放"恢复跟随', (tester) async {
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(musicScrollLyricsApp(player: player));
    await advanceFrames(tester);

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
    await advanceFrames(tester);
    expect(find.text('回到当前播放'), findsNothing);
    expect(
      tester.widget<ListView>(find.byType(ListView)).controller!.offset,
      isNot(wheelOffset),
    );
  });

  testWidgets('滚轮滚动同样暂停跟随，不被立即回拉', (tester) async {
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(musicScrollLyricsApp(player: player));
    await advanceFrames(tester);

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
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(
      musicScrollLyricsApp(
        player: player,
        settings: PortalLyricVisualSettings.defaults.copyWith(visibleLines: 1),
      ),
    );
    await advanceFrames(tester);
    final oneLineSlot =
        tester
            .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
            .style!
            .fontSize!;

    await tester.pumpWidget(
      musicScrollLyricsApp(
        player: player,
        settings: PortalLyricVisualSettings.defaults.copyWith(visibleLines: 9),
      ),
    );
    await advanceFrames(tester);
    final nineLineSlot =
        tester
            .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
            .style!
            .fontSize!;

    // 行数只属于多行歌词形态：滚动模式下改行数不得改变行高/字号。
    expect(nineLineSlot, oneLineSlot);
  });

  testWidgets('歌词位置决定文字块锚点与文本排列（居中/居左/居右）', (tester) async {
    final player = MusicScrollLyricsFakeAudioPlayback(
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
      musicScrollLyricsApp(
        player: player,
        textAlign: TextAlign.left,
        lyrics: lines,
      ),
    );
    await advanceFrames(tester);
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
      musicScrollLyricsApp(
        player: player,
        textAlign: TextAlign.left,
        blockAnchor: Alignment.centerLeft,
        lyrics: lines,
      ),
    );
    await advanceFrames(tester);
    expect(tester.getTopLeft(find.text(long)).dx, column().left);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .textAlign,
      TextAlign.left,
    );

    // 居右锚点：文字块贴住歌词列右边缘，文本右对齐，长短行共享块右边缘。
    await tester.pumpWidget(
      musicScrollLyricsApp(
        player: player,
        textAlign: TextAlign.left,
        blockAnchor: Alignment.centerRight,
        lyrics: lines,
      ),
    );
    await advanceFrames(tester);
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
    // 在读行字号更大时长句会折行，填充管线按可视行切片渲染，整句文本
    // 不再对应单个 Text：对齐断言改为按行切片定位（每行在行盒内居中，
    // 与整块居中一致）。
    await tester.pumpWidget(
      musicScrollLyricsApp(
        player: player,
        textAlign: TextAlign.left,
        scrollMode: false,
        lyrics: lines,
      ),
    );
    await advanceFrames(tester);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .textAlign,
      TextAlign.center,
    );
    final box = tester.getRect(find.byType(MusicImmersiveLyrics));
    expect(tester.getCenter(find.textContaining('这一句明显')).dx, box.center.dx);
  });

  testWidgets('歌词区上下边缘做渐隐处理，避免被顶栏底栏硬切', (tester) async {
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(musicScrollLyricsApp(player: player));
    await advanceFrames(tester);

    final fade = tester.widget<ShaderMask>(
      find.byKey(const ValueKey('music-lyric-edge-fade')),
    );
    // dstIn：遮罩两端透明，歌词行在上下边缘逐步淡出。
    expect(fade.blendMode, BlendMode.dstIn);
  });

  testWidgets('行距设置只改变相邻行之间的空隙', (tester) async {
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);

    Future<double> gapFor(double lineSpacing) async {
      await tester.pumpWidget(
        musicScrollLyricsApp(
          player: player,
          settings: PortalLyricVisualSettings.defaults.copyWith(
            lineSpacing: lineSpacing,
          ),
        ),
      );
      await advanceFrames(tester);
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
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);

    await tester.pumpWidget(
      musicScrollLyricsApp(
        player: player,
        settings: PortalLyricVisualSettings.defaults.copyWith(
          currentPaint: const LyricPaint.vertical(0xFFFF0000, 0xFF0000FF),
          inactivePaint: const LyricPaint.solid(0xFF00FF00),
        ),
      ),
    );
    await advanceFrames(tester);

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
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(
      musicScrollLyricsApp(
        player: player,
        settings: PortalLyricVisualSettings.defaults.copyWith(),
      ),
    );
    await advanceFrames(tester);

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .style!
          .color,
      const Color(0xFFFFFFFF),
    );
    expect(
      tester.widget<Text>(find.text('Lyric 9')).style!.color,
      const Color(
        0xFFFFFFFF,
      ).withValues(alpha: PortalLyricVisualSettings.defaults.inactiveOpacity),
    );
    // 默认 80%：非当前句仍可辨认，改默认值时上面的断言随之跟随。
    expect(PortalLyricVisualSettings.defaults.inactiveOpacity, 0.8);
  });

  testWidgets('原文与译文各自独立使用上下渐变', (tester) async {
    final player = MusicScrollLyricsFakeAudioPlayback(
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
      musicScrollLyricsApp(
        player: player,
        lyrics: lyrics,
        settings: PortalLyricVisualSettings.defaults.copyWith(
          currentPaint: const LyricPaint.vertical(0xFFFF0000, 0xFF0000FF),
        ),
      ),
    );
    await tester.pump();

    // 原文走双层填充画法（未唱层 + 读色层，文本出现两次）；
    // 译文不参与逐字填充，仅整行套自己的竖向渐变遮罩。
    expect(find.text('Hello world'), findsNWidgets(2));
    expect(find.text('你好世界'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('music-lyric-word-fill-layered')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('music-lyric-translation-gradient')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('歌词延迟校准把行切换整体后移', (tester) async {
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(milliseconds: 3400),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(musicScrollLyricsApp(player: player));
    await advanceFrames(tester);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .data,
      'Lyric 3',
    );

    await tester.pumpWidget(
      musicScrollLyricsApp(
        player: player,
        settings: PortalLyricVisualSettings.defaults.copyWith(offsetMs: 500),
      ),
    );
    await advanceFrames(tester);
    // 有效位置回退到 2.9s：当前行回到第 2 句。
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .data,
      'Lyric 2',
    );
  });

  testWidgets('焦点行锚点决定当前行在视口中的位置', (tester) async {
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);

    Future<double> anchorFraction(double anchor) async {
      await tester.pumpWidget(
        musicScrollLyricsApp(
          player: player,
          settings: PortalLyricVisualSettings.defaults.copyWith(
            focusAnchor: anchor,
          ),
        ),
      );
      await advanceFrames(tester);
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
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);

    Future<(double, double)> fontsFor(int fontSizePx) async {
      await tester.pumpWidget(
        musicScrollLyricsApp(
          player: player,
          settings: PortalLyricVisualSettings.defaults.copyWith(
            fontSizePx: fontSizePx,
          ),
        ),
      );
      await advanceFrames(tester);
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
    final player = MusicScrollLyricsFakeAudioPlayback(
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
        musicScrollLyricsApp(
          player: player,
          lyrics: translated,
          settings: PortalLyricVisualSettings.defaults.copyWith(
            translationEnabled: translationEnabled,
          ),
        ),
      );
      await advanceFrames(tester);
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
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(milliseconds: 3400),
    );
    addTearDown(player.dispose);
    // 无覆盖时 3.4s 落在第 3 行。
    await tester.pumpWidget(musicScrollLyricsApp(player: player));
    await advanceFrames(tester);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .data,
      'Lyric 3',
    );

    // 曲目级覆盖 500ms：有效位置回退到 2.9s，当前行回到第 2 行。
    await tester.pumpWidget(
      musicScrollLyricsApp(player: player, trackOffsetMs: 500),
    );
    await advanceFrames(tester);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .data,
      'Lyric 2',
    );

    // 曲目级覆盖优先：全局校准 -200ms 不影响覆盖生效。
    await tester.pumpWidget(
      musicScrollLyricsApp(
        player: player,
        trackOffsetMs: 500,
        settings: PortalLyricVisualSettings.defaults.copyWith(offsetMs: -200),
      ),
    );
    await advanceFrames(tester);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('music-lyric-active')))
          .data,
      'Lyric 2',
    );
  });

  testWidgets('长按行菜单提供复制歌词与延迟微调', (tester) async {
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);
    final adjustments = <int>[];
    await tester.pumpWidget(
      musicScrollLyricsApp(
        player: player,
        onAdjustLyricOffset: adjustments.add,
      ),
    );
    await advanceFrames(tester);

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
}
