import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/bootstrap.dart';
import 'package:omninest/app/preferences/app_bootstrap_data.dart';
import 'package:omninest/core/widgets/brand_logo.dart';

/// 启动画面有入场动画与最短可见时长，且进度条是不确定态（常驻动画），
/// 因此加载态一律不能用 `pumpAndSettle`：它会一直等动画收敛。
/// 取值只要求「大于实现里的最短可见时长」，不与具体毫秒数耦合。
const Duration _splashFloor = Duration(seconds: 1);

void main() {
  testWidgets('加载期展示带品牌标记与入场动画的启动画面', (tester) async {
    final pending = Completer<AppBootstrapData>();
    await tester.pumpWidget(
      AppBootstrapGate(
        loader: () => pending.future,
        builder: (_) => const MaterialApp(home: Text('ready')),
      ),
    );
    await tester.pump();

    // 启动画面是图形标记的主要落点：常驻外壳已不承载品牌，冷启动这一屏
    // 必须补上，否则标记只剩登录页一个出口。
    expect(find.byType(BrandLogo), findsOneWidget);
    expect(find.text('OmniNest'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // 入场动画：标记淡入缩放、字标上浮，不是静止的静态页。用 findsWidgets
    // 而非精确计数，避免把框架内部可能出现的过渡组件算作差异。
    expect(find.byType(FadeTransition), findsWidgets);
    expect(find.byType(ScaleTransition), findsWidgets);
    expect(find.byType(SlideTransition), findsWidgets);

    pending.complete(const AppBootstrapData());
    await tester.pump(_splashFloor);
    await tester.pump();

    expect(find.text('ready'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('数据先于动画就绪时启动画面仍走完最短可见时长', (tester) async {
    await tester.pumpWidget(
      AppBootstrapGate(
        // 本地偏好读取是同步量级，这里模拟「数据瞬间就绪」。
        loader: () async => const AppBootstrapData(),
        builder: (_) => const MaterialApp(home: Text('ready')),
      ),
    );
    await tester.pump();
    expect(find.byType(BrandLogo), findsOneWidget);

    // 动画播到一半时数据早已就绪，但界面不应提前切走。
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('ready'), findsNothing);

    await tester.pump(_splashFloor);
    await tester.pump();
    expect(find.text('ready'), findsOneWidget);
  });

  testWidgets('关闭系统动效时启动画面只留一帧确认', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(
      AppBootstrapGate(
        loader: () async => const AppBootstrapData(),
        builder: (_) => const MaterialApp(home: Text('ready')),
      ),
    );
    await tester.pump();
    expect(find.byType(BrandLogo), findsOneWidget);

    // 静止画面不按动画时长拖住用户，只留一帧确认即可进入应用。
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.text('ready'), findsOneWidget);
  });

  testWidgets('启动数据加载完成后挂载应用', (tester) async {
    await tester.pumpWidget(
      AppBootstrapGate(
        loader:
            () async => const AppBootstrapData(
              themeModeName: 'dark',
              languageCode: 'en',
            ),
        builder:
            (data) => MaterialApp(
              home: Text('${data.themeModeName}:${data.languageCode}'),
            ),
      ),
    );
    await tester.pump(_splashFloor);
    await tester.pump();

    expect(find.text('dark:en'), findsOneWidget);
  });

  testWidgets('启动失败后可以重试并恢复', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      AppBootstrapGate(
        loader: () async {
          attempts++;
          if (attempts == 1) {
            throw StateError('media unavailable');
          }
          return const AppBootstrapData();
        },
        builder: (_) => const MaterialApp(home: Text('ready')),
      ),
    );
    // 错误路径不等最短可见时长，失败原因立即呈现。
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump(_splashFloor);
    await tester.pump();

    expect(find.text('ready'), findsOneWidget);
    expect(attempts, 2);
  });
}
