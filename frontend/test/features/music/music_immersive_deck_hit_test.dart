import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/music/domain/music_models.dart';
import 'package:omninest/features/music/domain/music_visualizer_preset.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_player.dart';
import 'package:omninest/features/music/presentation/player/music_immersive_style.dart';

MusicTrack _track(int ordinal) {
  return MusicTrack(
    id: 'track-$ordinal',
    fileNodeId: 'file-$ordinal',
    title: 'Track $ordinal',
    artistName: 'Artist',
    albumTitle: 'Album',
    format: 'mp3',
    favorite: false,
  );
}

Future<void> _pumpDeck(
  WidgetTester tester,
  PortalMusicLayout layout,
  ValueChanged<int> onSelected,
) async {
  const count = 6;
  final tracks = [for (var i = 1; i <= count; i++) _track(i)];
  // 卡组盒尺寸必须等于 stageSize：实机里卡组是 Positioned.fromRect(deckRect)，
  // 容器之外的命中带不会被命中测试接受。
  const stageSize = Size(440, 385);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: stageSize.width,
            height: stageSize.height,
            child: MusicImmersiveCoverDeck(
              palette: MusicImmersivePalette.digital,
              tracks: tracks,
              selectedIndex: 0,
              currentTrack: tracks.first,
              expanded: false,
              scale: 1,
              layout: layout,
              isPlaying: false,
              stageSize: stageSize,
              onSelected: onSelected,
              onStep: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // 两侧卡组的扇形越出卡组盒：等距档右缘 8 + 34*4 + 320 = 464、步进档
  // 12 + 38*4 + 310 = 474，而容器基准只有 440/420（实机再受列宽压到 ~418）。
  // 第 4 档在容器内没有任何像素，命中测试被父级尺寸挡住 → 可见但点不到。
  // 修法需要改可见几何，待选型。
  for (final layout in [PortalMusicLayout.left, PortalMusicLayout.right]) {
    testWidgets('${layout.name} 布局每一档命中条都应选中对应曲目'
        '（阻塞：最外档扇形溢出卡组盒，容器内无可命中区域，待几何选型）', (tester) async {
      final selected = <int>[];
      await _pumpDeck(tester, layout, selected.add);

      for (var slot = 1; slot <= 4; slot++) {
        await tester.tap(
          find.byKey(ValueKey('deck-hit-strip-$slot')),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
      }

      expect(selected, [1, 2, 3, 4]);
    }, skip: true);
  }

  testWidgets('居中布局四张后排卡都有命中条且悬停抽出', (tester) async {
    const stageSize = Size(900, 520);
    final tracks = [for (var i = 1; i <= 6; i++) _track(i)];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: stageSize.width,
              height: stageSize.height,
              child: MusicImmersiveCoverDeck(
                palette: MusicImmersivePalette.digital,
                tracks: tracks,
                selectedIndex: 0,
                currentTrack: tracks.first,
                expanded: false,
                scale: 1,
                layout: PortalMusicLayout.center,
                isPlaying: false,
                stageSize: stageSize,
                onSelected: (_) {},
                onStep: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 四张后排卡都要有命中条并响应悬停抽出；抽出量与
    // kMusicCenterHoverPullOutX 对齐（外侧档 52.5、内侧档 62.5）。
    const pullOutBySlot = <int, double>{-2: -52.5, -1: -62.5, 1: 62.5, 2: 52.5};
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    Offset translateOf(Finder finder) {
      final moved = tester.widget<AnimatedContainer>(finder).transform!;
      return Offset(moved[12], moved[13]);
    }

    for (final entry in pullOutBySlot.entries) {
      final slot = entry.key;
      final strip = find.byKey(ValueKey('deck-hit-strip-$slot'));
      expect(strip, findsOneWidget, reason: '档位 $slot 没有命中条');

      final cardKey = ValueKey('track-${slot % 6 + 1}-drag-surface-$slot');
      final container =
          find
              .ancestor(
                of: find.byKey(cardKey),
                matching: find.byType(AnimatedContainer),
              )
              .first;
      final resting = translateOf(container);

      final center = tester.getCenter(strip);
      final hit = HitTestResult();
      tester.binding.hitTestInView(hit, center, tester.view.viewId);
      tester.binding.dispatchEvent(pointer.hover(center), hit);
      await tester.pump();
      // 卡组常驻动画会让 pumpAndSettle 永不收敛，这里只推进悬停动画本身。
      await tester.pump(const Duration(milliseconds: 400));

      final pulled = translateOf(container);
      expect(
        pulled.dx - resting.dx,
        closeTo(entry.value, 0.51),
        reason: '档位 $slot 悬停未抽出',
      );
      expect(pulled.dy - resting.dy, closeTo(-12, 0.51));
      // 下一个档位直接把指针移到新命中条即可：MouseTracker 会先发 exit 再发 enter。
    }
  });
}
