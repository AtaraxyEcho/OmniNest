import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/features/portal/presentation/widgets/portal_visual_widgets.dart';

void main() {
  // 悬停缩放接线检查用的封面卡环境：主题取调色板，ProviderScope 供
  // ConsumerWidget 的封面缓存管理器解析。
  Future<void> pumpCover(WidgetTester tester, {double? contentScale}) async {
    PortalVisualPalette? palette;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          home: Builder(
            builder: (context) {
              palette ??= PortalVisualPalette.of(context);
              return Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 320,
                    height: 420,
                    child: PortalGradientCover(
                      palette: palette!,
                      title: 'title',
                      subtitle: 'subtitle',
                      imageUrl: 'https://example.test/cover.jpg',
                      contentScale: contentScale ?? 1.0,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('contentScale 只驱动封面图层的内容裁切缩放', (tester) async {
    await pumpCover(tester);

    // 有图路径：缩放节点唯一，且位于 FittedBox > ClipRect 内——图片画幅
    // 被钉死，放大只作用于内部像素（Photos 照片卡同构），氛围底图与
    // 遮罩不参与缩放。
    final artScale = find.byType(AnimatedScale);
    expect(artScale, findsOneWidget);
    expect(
      find.descendant(of: find.byType(FittedBox), matching: artScale),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(ClipRect), matching: artScale),
      findsOneWidget,
    );
    final scaleWidget = tester.widget<AnimatedScale>(artScale);
    expect(scaleWidget.scale, 1.0);
    expect(scaleWidget.duration, MotionToken.normal);
    expect(scaleWidget.curve, MotionToken.curve);

    await pumpCover(tester, contentScale: 1.05);
    expect(tester.widget<AnimatedScale>(artScale).scale, 1.05);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无图回退分支不引入缩放节点', (tester) async {
    PortalVisualPalette? palette;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: OmniNestTheme.dark(),
          home: Builder(
            builder: (context) {
              palette ??= PortalVisualPalette.of(context);
              return Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 320,
                    height: 420,
                    child: PortalGradientCover(
                      palette: palette!,
                      title: 'title',
                      subtitle: 'subtitle',
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AnimatedScale), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
