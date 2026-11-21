import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/video/presentation/widgets/movie_player_center_controls.dart';

/// 样例 `.v-flash`（`desktop.css:324`）：92×92 圆形图标，.7s 内从
/// scale(.7) 放大到 1.5 并淡出；只在播放/暂停切换时挂上去。
///
/// 顺带锁住两条性能约束：`BackdropFilter` 只在 92×92 圆内生效（不给整屏
/// 叠加取样），减动效时既不渲染也不注册 ticker。
void main() {
  Widget host({required bool reduce}) => MediaQuery(
    data: MediaQueryData(disableAnimations: reduce),
    child: const MaterialApp(
      home: Stack(
        children: [MoviePlayerCenterFlash(icon: Icons.pause_rounded)],
      ),
    ),
  );

  testWidgets('中央闪现是 92×92 圆形图标，700ms 内淡到全透明', (tester) async {
    await tester.pumpWidget(host(reduce: false));
    await tester.pump();

    final flash = find.byKey(const ValueKey('player-center-flash'));
    expect(flash, findsOneWidget);
    expect(tester.getSize(flash), const Size(92, 92));
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    // 样例的 blur(10px) 必须接上，且被圆角裁剪限制在这枚 OSD 之内。
    expect(
      find.descendant(
        of: find.byType(MoviePlayerCenterFlash),
        matching: find.byType(BackdropFilter),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(MoviePlayerCenterFlash),
        matching: find.byType(ClipRRect),
      ),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 700));
    final opacity = tester.widget<Opacity>(
      find
          .descendant(
            of: find.byType(MoviePlayerCenterFlash),
            matching: find.byType(Opacity),
          )
          .at(0),
    );
    expect(opacity.opacity, 0);
  });

  testWidgets('减动效下不挂闪现层，也不注册 ticker', (tester) async {
    await tester.pumpWidget(host(reduce: true));
    await tester.pump();

    expect(find.byKey(const ValueKey('player-center-flash')), findsNothing);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
