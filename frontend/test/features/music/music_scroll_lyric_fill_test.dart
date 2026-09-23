import 'dart:ui' as ui show Image, ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_visualizer_preset.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_layout_spec.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_lyrics.dart';

import 'support/music_scroll_lyrics_harness.dart';

/// 逐字填充、复刻形态双色与在读行附属元素的行为基线，
/// 与 `music_scroll_lyrics_test.dart` 共用 `support/` 里的驱动与像素探针。

void main() {
  testWidgets('逐字填充按已完成词时长推进（纯色单层遮罩）', (tester) async {
    // 行 3.0s–4.0s，词级仅覆盖前 0.4s：位置 3.2s 的填充比例 = 0.2/0.4 = 50%
    //（曲线见 music_models_test 的 fillProgressAt 断言，非线性 20%）。
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 3),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(
      musicScrollLyricsApp(player: player, wordTimeline: true),
    );
    await advanceFrames(tester);

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
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 3),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(
      musicScrollLyricsApp(
        player: player,
        wordTimeline: true,
        settings: PortalLyricVisualSettings.defaults.copyWith(
          wordFillEnabled: false,
        ),
      ),
    );
    await advanceFrames(tester);
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
    final plainPlayer = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(milliseconds: 3200),
    );
    addTearDown(plainPlayer.dispose);
    await tester.pumpWidget(musicScrollLyricsApp(player: plainPlayer));
    await advanceFrames(tester);
    plainPlayer.emit(const Duration(milliseconds: 3210));
    await tester.pump();
    expect(find.byKey(const ValueKey('music-lyric-word-fill')), findsOneWidget);

    // 有词级数据但暂停：填充遮罩隐藏，在读行整行用读色。
    final pausedPlayer = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 3),
    );
    addTearDown(pausedPlayer.dispose);
    await tester.pumpWidget(
      musicScrollLyricsApp(player: pausedPlayer, wordTimeline: true),
    );
    await advanceFrames(tester);
    pausedPlayer.emit(const Duration(milliseconds: 3200));
    await tester.pump();
    expect(find.byKey(const ValueKey('music-lyric-word-fill')), findsOneWidget);
    await pausedPlayer.pause();
    pausedPlayer.emit(const Duration(milliseconds: 3300));
    await tester.pump();
    expect(find.byKey(const ValueKey('music-lyric-word-fill')), findsNothing);
  });

  testWidgets('填充与上下渐变共存：双层叠加各自保留渐变', (tester) async {
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 3),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(
      musicScrollLyricsApp(
        player: player,
        wordTimeline: true,
        settings: PortalLyricVisualSettings.defaults.copyWith(
          currentPaint: const LyricPaint.vertical(0xFFFF0000, 0xFF0000FF),
        ),
      ),
    );
    await advanceFrames(tester);
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

  testWidgets('双层填充画法两层文字完全对齐（墨迹边距不得叠加）', (tester) async {
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 3),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(
      musicScrollLyricsApp(
        player: player,
        wordTimeline: true,
        settings: PortalLyricVisualSettings.defaults.copyWith(
          currentPaint: const LyricPaint.vertical(0xFFFF0000, 0xFF0000FF),
        ),
      ),
    );
    await advanceFrames(tester);
    player.emit(const Duration(milliseconds: 3200));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('music-lyric-word-fill-layered')),
      findsOneWidget,
    );
    // 双层画法渲染两份同文文本：底层非当前句色与顶层读色。若某一层
    // 重复包墨迹边距，其字形会整体下移（回归表现为"叠字"）。
    final tops =
        tester
            .renderObjectList<RenderParagraph>(find.text('Lyric 3'))
            .map((paragraph) => paragraph.localToGlobal(Offset.zero).dy)
            .toList();
    expect(tops.length, 2);
    expect((tops.first - tops.last).abs(), lessThan(0.5));
  });

  testWidgets('折行在读行按可视行切片渲染且行盒顺序堆叠', (tester) async {
    // Ahem 字体每字形宽 = 字号：48px 下 "AAAA AAAA AAAA AAAA"（912px）
    // 超出 800px 视口，折为 "AAAA AAAA AAAA"（768px）+ "AAAA"（192px）。
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 1),
    );
    addTearDown(player.dispose);
    final lyrics = <MusicLyricLine>[
      const MusicLyricLine(position: Duration.zero, text: 'X'),
      const MusicLyricLine(
        position: Duration(seconds: 1),
        text: 'AAAA AAAA AAAA AAAA',
      ),
      const MusicLyricLine(position: Duration(seconds: 2), text: 'X'),
    ];
    await tester.pumpWidget(
      musicScrollLyricsApp(
        player: player,
        lyrics: lyrics,
        fontFamily: 'Ahem',
        settings: PortalLyricVisualSettings.defaults.copyWith(
          fontSizePx: 48,
          currentFontSizePx: 48,
        ),
      ),
    );
    await advanceFrames(tester);

    expect(find.text('AAAA AAAA AAAA'), findsOneWidget);
    expect(find.text('AAAA'), findsOneWidget);
    final firstTop = tester.getTopLeft(find.text('AAAA AAAA AAAA')).dy;
    final secondTop = tester.getTopLeft(find.text('AAAA')).dy;
    // 行盒按 strut 行高顺序堆叠，不重叠、不错位。
    expect(secondTop - firstTop, closeTo(48 * 1.18, 0.5));
  });

  testWidgets('渐变在读行折行时每个可视行各自挂填充遮罩', (tester) async {
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 1),
    );
    addTearDown(player.dispose);
    final lyrics = <MusicLyricLine>[
      const MusicLyricLine(position: Duration.zero, text: 'X'),
      const MusicLyricLine(
        position: Duration(seconds: 1),
        text: 'AAAA AAAA AAAA AAAA',
      ),
      const MusicLyricLine(position: Duration(seconds: 2), text: 'X'),
    ];
    await tester.pumpWidget(
      musicScrollLyricsApp(
        player: player,
        lyrics: lyrics,
        fontFamily: 'Ahem',
        settings: PortalLyricVisualSettings.defaults.copyWith(
          fontSizePx: 48,
          currentFontSizePx: 48,
          currentPaint: const LyricPaint.vertical(0xFFB7FFE7, 0xFF7098A0),
        ),
      ),
    );
    await advanceFrames(tester);

    // 双层画法逐行挂载：首行沿用基础键，其余行带行号后缀。
    expect(
      find.byKey(const ValueKey('music-lyric-word-fill-layered')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('music-lyric-word-fill-layered-1')),
      findsOneWidget,
    );
  });

  testWidgets('折行逐字填充按行宽加权顺序推进（首行未满次行不动）', (tester) async {
    // 行时长 1s，位置进行到 50%：整段已唱宽度 = 0.5 ×（768 + 192）= 480px，
    // 全部落在首行（宽 768px），次行局部进度为 0，不得提前点亮。
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 1),
    );
    addTearDown(player.dispose);
    final lyrics = <MusicLyricLine>[
      const MusicLyricLine(position: Duration.zero, text: 'X'),
      const MusicLyricLine(
        position: Duration(seconds: 1),
        text: 'AAAA AAAA AAAA AAAA',
      ),
      const MusicLyricLine(position: Duration(seconds: 2), text: 'X'),
    ];
    await tester.pumpWidget(
      musicScrollLyricsApp(
        player: player,
        lyrics: lyrics,
        fontFamily: 'Ahem',
        settings: PortalLyricVisualSettings.defaults.copyWith(
          fontSizePx: 48,
          currentFontSizePx: 48,
        ),
      ),
    );
    await advanceFrames(tester);
    player.emit(const Duration(milliseconds: 1500));
    await tester.pump();

    // 次行行盒存在且保持未唱（切分行渲染本身保证了逐行推进的边界来源，
    // 行盒堆叠回归由上一条测试锚定）。
    expect(find.text('AAAA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('折行逐字填充与逐行渐变的视觉基线', (tester) async {
    // 渐变每个可视行完整走一遍、填充按行宽加权顺序推进：渲染结果以
    // 黄金文件锚定，回归时先核对折行边界与填充边界位置是否漂移。
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 1),
    );
    addTearDown(player.dispose);
    final lyrics = <MusicLyricLine>[
      const MusicLyricLine(position: Duration.zero, text: 'X'),
      const MusicLyricLine(
        position: Duration(seconds: 1),
        text: 'AAAA AAAA AAAA AAAA',
      ),
      const MusicLyricLine(position: Duration(seconds: 2), text: 'X'),
    ];
    await tester.pumpWidget(
      musicScrollLyricsApp(
        player: player,
        lyrics: lyrics,
        fontFamily: 'Ahem',
        settings: PortalLyricVisualSettings.defaults.copyWith(
          fontSizePx: 48,
          currentFontSizePx: 48,
          currentPaint: const LyricPaint.vertical(0xFFB7FFE7, 0xFF7098A0),
        ),
      ),
    );
    await advanceFrames(tester);
    player.emit(const Duration(milliseconds: 1500));
    await tester.pump();

    await expectLater(
      find.byType(MusicImmersiveLyrics),
      matchesGoldenFile('goldens/music_lyric_fill_wrapped_gradient.png'),
    );
  });

  testWidgets('折行逐字填充按词级时长衔接行间进度（次行不被宽度比例拖延）', (tester) async {
    // 词级时长刻意与行宽失衡：首行三组词只唱 0.3s（宽占 78%），次行一组词
    // 唱 0.7s（宽占 22%）。位置进行到 0.4s（总进度 40%）时次行按时间应已
    // 点亮约 14%；若错误地按行宽加权，次行会完全未唱（回归即"明显延迟"）。
    // 断言直接采样渲染像素：已唱区域为渐变读色（G 分量高于 R），未唱区域
    // 为非当前句色（G≈R）。
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 1),
    );
    addTearDown(player.dispose);
    const probeKey = ValueKey('music-lyric-pixel-probe');
    final lyrics = <MusicLyricLine>[
      const MusicLyricLine(position: Duration.zero, text: 'X'),
      const MusicLyricLine(
        position: Duration(seconds: 1),
        text: 'AAAA AAAA AAAA AAAA',
        words: <MusicLyricWord>[
          MusicLyricWord(
            offset: Duration.zero,
            duration: Duration(milliseconds: 100),
            text: 'AAAA ',
          ),
          MusicLyricWord(
            offset: Duration(milliseconds: 100),
            duration: Duration(milliseconds: 100),
            text: 'AAAA ',
          ),
          MusicLyricWord(
            offset: Duration(milliseconds: 200),
            duration: Duration(milliseconds: 100),
            text: 'AAAA ',
          ),
          MusicLyricWord(
            offset: Duration(milliseconds: 300),
            duration: Duration(milliseconds: 700),
            text: 'AAAA',
          ),
        ],
      ),
      const MusicLyricLine(position: Duration(seconds: 2), text: 'X'),
    ];
    await tester.pumpWidget(
      musicScrollLyricsApp(
        player: player,
        lyrics: lyrics,
        fontFamily: 'Ahem',
        repaintBoundaryKey: probeKey,
        settings: PortalLyricVisualSettings.defaults.copyWith(
          fontSizePx: 48,
          currentFontSizePx: 48,
          currentPaint: const LyricPaint.vertical(0xFFB7FFE7, 0xFF7098A0),
        ),
      ),
    );
    await advanceFrames(tester);
    player.emit(const Duration(milliseconds: 1400));
    await tester.pump();

    final renderBoundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(probeKey),
    );
    late final ui.Image image;
    await tester.binding.runAsync(() async {
      image = await renderBoundary.toImage(pixelRatio: 1);
    });
    final bytes = await tester.binding.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    expect(bytes, isNotNull);

    int greenMinusRed(Offset point) {
      final x = point.dx.round().clamp(0, image.width - 1);
      final y = point.dy.round().clamp(0, image.height - 1);
      final offset = (y * image.width + x) * 4;
      return bytes!.getUint8(offset + 1) - bytes.getUint8(offset);
    }

    // 次行 "AAAA"：字形只占行盒左侧 192px，左端约 14% 已唱（渐变读色，
    // G 分量高于 R），中段未唱（非当前句色，G≈R）。
    final secondLine = tester.getRect(find.text('AAAA').first);
    final firstLine = tester.getRect(find.text('AAAA AAAA AAAA').first);
    final filledDelta = greenMinusRed(
      Offset(secondLine.left + 8, secondLine.center.dy),
    );
    final unsungDelta = greenMinusRed(
      Offset(secondLine.left + 100, secondLine.center.dy),
    );
    expect(filledDelta, greaterThan(20));
    expect(unsungDelta.abs(), lessThan(12));

    // 首行在 0.3s 唱完，0.4s 时应整行点亮（右端也是读色）。
    final firstTailDelta = greenMinusRed(
      Offset(firstLine.left + firstLine.width * 0.9, firstLine.center.dy),
    );
    expect(firstTailDelta, greaterThan(20));
    image.dispose();
  });

  testWidgets('居左/居中/居右锚点下填充遮罩都按当前行挂载', (tester) async {
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 3),
    );
    addTearDown(player.dispose);

    Future<bool> fillPresentFor(Alignment anchor) async {
      await tester.pumpWidget(
        musicScrollLyricsApp(
          player: player,
          wordTimeline: true,
          blockAnchor: anchor,
        ),
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
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: Duration.zero,
    );
    addTearDown(player.dispose);
    final settings = PortalLyricVisualSettings.defaults.copyWith(
      currentPaint: const LyricPaint.solid(0xFFE7C86A),
      inactivePaint: const LyricPaint.solid(0xFF9AA7B8),
    );
    await tester.pumpWidget(
      musicScrollLyricsApp(
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
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: Duration.zero,
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(
      musicScrollLyricsApp(
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
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: Duration.zero,
    );
    addTearDown(player.dispose);
    final settings = PortalLyricVisualSettings.defaults.copyWith(
      currentPaint: const LyricPaint.vertical(0xFFB7FFE7, 0xFF7098A0),
    );
    await tester.pumpWidget(
      musicScrollLyricsApp(
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
  testWidgets('在读行不绘制左侧强调条（单行与多行一致）', (tester) async {
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: Duration.zero,
    );
    addTearDown(player.dispose);
    final spec = resolveMusicLyricSpec(PortalMusicLayout.left, 1);

    // 样例的左侧竖向强调条已整体移除：短歌词下它只是一根与内容无关的白线。
    // 断言只认「带左边框的装饰盒」，避免把底衬色带误判；时间参考胶囊
    // （样例 lyric-meta）本身带描边，按键排除。
    int leftBarCount() {
      return tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).where((
        box,
      ) {
        if (box.key == const ValueKey('music-lyric-aux-pill')) {
          return false;
        }
        final decoration = box.decoration;
        if (decoration is! BoxDecoration) {
          return false;
        }
        final border = decoration.border;
        return border is Border && border.left.width > 0;
      }).length;
    }

    Future<void> pumpLyrics(List<MusicLyricLine> lyrics) async {
      await tester.pumpWidget(
        musicScrollLyricsApp(player: player, spec: spec, lyrics: lyrics),
      );
      await tester.pump();
      await tester.pump();
    }

    await pumpLyrics(const <MusicLyricLine>[
      MusicLyricLine(position: Duration.zero, text: '纯音乐，请欣赏'),
    ]);
    expect(leftBarCount(), 0);

    await pumpLyrics(const <MusicLyricLine>[
      MusicLyricLine(position: Duration.zero, text: '第一行'),
      MusicLyricLine(position: Duration(seconds: 30), text: '第二行'),
    ]);
    expect(leftBarCount(), 0);
  });

  testWidgets('在读行时间标签默认关闭，开启后只在两侧布局的读行出现', (tester) async {
    const lyrics = <MusicLyricLine>[
      MusicLyricLine(position: Duration(seconds: 12), text: '第一句'),
      MusicLyricLine(position: Duration(seconds: 40), text: '第二句'),
    ];

    Future<void> pumpWith(MusicLyricSpec spec) async {
      final player = MusicScrollLyricsFakeAudioPlayback(
        initialPosition: const Duration(seconds: 13),
      );
      addTearDown(player.dispose);
      await tester.pumpWidget(
        musicScrollLyricsApp(player: player, spec: spec, lyrics: lyrics),
      );
      await tester.pump();
      await tester.pump();
    }

    // 默认关闭：不渲染时间胶囊，也不预留其高度。
    await pumpWith(resolveMusicLyricSpec(PortalMusicLayout.left, 1));
    expect(find.byIcon(Icons.graphic_eq), findsNothing);
    expect(find.text('00:12.0'), findsNothing);

    // 开启后：在读行显示 `mm:ss.d` 时间胶囊；样例里的「重复本句」入口已删除，
    // 跳回本句仍由整行的 onTap 承接。
    await pumpWith(
      resolveMusicLyricSpec(PortalMusicLayout.left, 1, timeTagEnabled: true),
    );
    expect(find.byIcon(Icons.graphic_eq), findsOneWidget);
    expect(find.text('00:12.0'), findsOneWidget);
    expect(find.text('00:40.0'), findsNothing);
    expect(find.text('重复本句'), findsNothing);
  });

  testWidgets('居中固定窗口不放时间标签', (tester) async {
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 13),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(
      musicScrollLyricsApp(
        player: player,
        // 居中布局即使开关开着也不预留时间标签位（样例为固定四行窗口）。
        spec: resolveMusicLyricSpec(
          PortalMusicLayout.center,
          1,
          timeTagEnabled: true,
        ),
        scrollMode: false,
        textAlign: TextAlign.center,
        blockAnchor: Alignment.center,
        lyrics: const <MusicLyricLine>[
          MusicLyricLine(position: Duration(seconds: 12), text: '第一句'),
          MusicLyricLine(position: Duration(seconds: 40), text: '第二句'),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.graphic_eq), findsNothing);
  });

  testWidgets('在读行底衬按行内容取高，不随行槽漂移', (tester) async {
    // 纯音乐这类单行短歌词：底衬必须包住文字本身（上下各扩 paddingY），
    // 而不是按整行槽钉边距——行槽里含行距、译文预留与时间标签位。
    Future<({MusicLyricSpec spec, Rect band, Rect text})> pumpAndMeasure({
      required bool timeTag,
    }) async {
      final player = MusicScrollLyricsFakeAudioPlayback(
        initialPosition: Duration.zero,
      );
      addTearDown(player.dispose);
      final spec = resolveMusicLyricSpec(
        PortalMusicLayout.left,
        1,
        timeTagEnabled: timeTag,
      );
      await tester.pumpWidget(
        musicScrollLyricsApp(
          player: player,
          spec: spec,
          lyrics: const <MusicLyricLine>[
            MusicLyricLine(position: Duration.zero, text: '纯音乐，请欣赏'),
            MusicLyricLine(position: Duration(seconds: 30), text: '第二句'),
          ],
        ),
      );
      await tester.pump();
      await tester.pump();
      final band = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .firstWhere(
            (box) =>
                box.decoration is BoxDecoration &&
                (box.decoration as BoxDecoration).color ==
                    const Color(0x660C0E11),
          );
      return (
        band: tester.getRect(find.byWidget(band)),
        text: tester.getRect(find.text('纯音乐，请欣赏')),
        spec: spec,
      );
    }

    final off = await pumpAndMeasure(timeTag: false);
    // 底衬包住文字行盒并四向至少扩出 padding，且与文字同一水平轴心：
    // 行槽里的行距、译文预留与时间标签位都不应参与色块取高。
    expect(
      off.band.top,
      lessThanOrEqualTo(off.text.top - off.spec.activeLinePaddingY + 1),
    );
    expect(
      off.band.bottom,
      greaterThanOrEqualTo(off.text.bottom + off.spec.activeLinePaddingY - 1),
    );
    expect((off.band.center.dy - off.text.center.dy).abs(), lessThan(1.5));
    expect(off.band.left, lessThan(off.text.left));

    // 开启时间标签后底衬把标签一起包住：只按内容增长，
    // 不再被行槽的其余预留撑高。
    final on = await pumpAndMeasure(timeTag: true);
    expect(on.band.height, greaterThan(off.band.height));
    expect(
      on.band.height - off.band.height,
      closeTo(on.spec.activeAuxGap + on.spec.activeAuxReserve, 2),
    );
  });

  testWidgets('跨可视行的词元时长按字符占比拆分，次行不再锁在未唱', (tester) async {
    // 折行为 14 + 4 字符：第二个词元 "A AAAA" 从第 13 个字符起，跨过换行点。
    // 整段时长记给首行会让次行权重为 0，被唱时仍停在非当前句色（"填不满"），
    // 等下一个变化点再整块跳变。按字符占比拆分后次行应在演唱到达时就开始点亮。
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 1),
    );
    addTearDown(player.dispose);
    const probeKey = ValueKey('music-lyric-pixel-probe');
    final lyrics = <MusicLyricLine>[
      const MusicLyricLine(position: Duration.zero, text: 'X'),
      const MusicLyricLine(
        position: Duration(seconds: 1),
        text: 'AAAA AAAA AAAA AAAA',
        words: <MusicLyricWord>[
          MusicLyricWord(
            offset: Duration.zero,
            duration: Duration(milliseconds: 100),
            text: 'AAAA AAAA AAA',
          ),
          MusicLyricWord(
            offset: Duration(milliseconds: 100),
            duration: Duration(milliseconds: 700),
            text: 'A AAAA',
          ),
        ],
      ),
      const MusicLyricLine(position: Duration(seconds: 2), text: 'X'),
    ];
    await tester.pumpWidget(
      musicScrollLyricsApp(
        player: player,
        lyrics: lyrics,
        fontFamily: 'Ahem',
        repaintBoundaryKey: probeKey,
        settings: PortalLyricVisualSettings.defaults.copyWith(
          fontSizePx: 48,
          currentFontSizePx: 48,
          currentPaint: const LyricPaint.vertical(0xFFB7FFE7, 0xFF7098A0),
        ),
      ),
    );
    await advanceFrames(tester);
    // 结构前置断言：确认确实折成 14 + 4 两行，词元才可能跨行。
    // 每行有 ambient + active 两份同文副本，按 .first 取其一。
    expect(find.text('AAAA AAAA AAAA'), findsAtLeastNWidgets(1));
    expect(find.text('AAAA'), findsAtLeastNWidgets(1));

    // 演唱到行内 500ms：整行进度 500/800。
    player.emit(const Duration(milliseconds: 1500));
    await tester.pump();

    final (image, delta) = await pixelProbe(tester, probeKey);
    addTearDown(image.dispose);
    final secondLine = tester.getRect(find.text('AAAA').first);
    final firstLine = tester.getRect(find.text('AAAA AAAA AAAA').first);

    // 次行左端已点亮、右端仍未唱；首行整行唱完。
    expect(
      delta(Offset(secondLine.left + 8, secondLine.center.dy)),
      greaterThan(20),
    );
    expect(
      delta(
        Offset(secondLine.left + secondLine.width * 0.9, secondLine.center.dy),
      ).abs(),
      lessThan(12),
    );
    expect(
      delta(
        Offset(firstLine.left + firstLine.width * 0.95, firstLine.center.dy),
      ),
      greaterThan(20),
    );
  });

  testWidgets('个别词元与行文本失配时其余行仍按时间加权', (tester) async {
    // 词级时长刻意与行宽失衡：首行 14 字符只唱 100/550，次行 4 字符唱 400/550。
    // 失配词 "ZZZZ" 的 50ms 仍留在总时长里（与 fillStateAt 口径一致），按比例
    // 摊回两行。整行退回行宽加权时次行要等到进度 672/864=77.8% 才亮；按时间加权
    // 时它在 110/550=20% 就开始点亮。
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 1),
    );
    addTearDown(player.dispose);
    const probeKey = ValueKey('music-lyric-pixel-probe');
    final lyrics = <MusicLyricLine>[
      const MusicLyricLine(position: Duration.zero, text: 'X'),
      const MusicLyricLine(
        position: Duration(seconds: 1),
        text: 'ABCD EFGH IJKL MNOP',
        words: <MusicLyricWord>[
          MusicLyricWord(
            offset: Duration.zero,
            duration: Duration(milliseconds: 100),
            text: 'ABCD EFGH IJKL',
          ),
          // 行文本中不存在：只丢该词自身的归属，不再作废整行时间加权。
          MusicLyricWord(
            offset: Duration(milliseconds: 100),
            duration: Duration(milliseconds: 50),
            text: 'ZZZZ',
          ),
          MusicLyricWord(
            offset: Duration(milliseconds: 150),
            duration: Duration(milliseconds: 400),
            text: 'MNOP',
          ),
        ],
      ),
      const MusicLyricLine(position: Duration(seconds: 2), text: 'X'),
    ];
    await tester.pumpWidget(
      musicScrollLyricsApp(
        player: player,
        lyrics: lyrics,
        fontFamily: 'Ahem',
        repaintBoundaryKey: probeKey,
        settings: PortalLyricVisualSettings.defaults.copyWith(
          fontSizePx: 48,
          currentFontSizePx: 48,
          currentPaint: const LyricPaint.vertical(0xFFB7FFE7, 0xFF7098A0),
        ),
      ),
    );
    await advanceFrames(tester);
    expect(find.text('ABCD EFGH IJKL'), findsAtLeastNWidgets(1));

    // 行内 200ms：整行进度 200/550 = 36.4%。
    player.emit(const Duration(milliseconds: 1200));
    await tester.pump();

    final (image, delta) = await pixelProbe(tester, probeKey);
    addTearDown(image.dispose);
    final firstLine = tester.getRect(find.text('ABCD EFGH IJKL').first);
    final secondLine = tester.getRect(find.text('MNOP').first);
    // 首行已唱完（右端读色），次行左端已开始点亮。
    expect(
      delta(
        Offset(firstLine.left + firstLine.width * 0.95, firstLine.center.dy),
      ),
      greaterThan(20),
    );
    expect(
      delta(Offset(secondLine.left + 8, secondLine.center.dy)),
      greaterThan(20),
    );
  });

  testWidgets('点击歌词行跳转加回生效的歌词延迟', (tester) async {
    final player = MusicScrollLyricsFakeAudioPlayback(
      initialPosition: const Duration(seconds: 10),
    );
    addTearDown(player.dispose);
    await tester.pumpWidget(
      musicScrollLyricsApp(player: player, trackOffsetMs: 500),
    );
    await advanceFrames(tester);

    await tester.tap(find.text('Lyric 12'));
    await tester.pump();

    // 行选中按 position - 500ms 判定，跳到第 12 句必须落在 12.5s，
    // 否则播放后立刻又被算回上一句。
    expect(player.state.position, const Duration(milliseconds: 12500));
  });
}
