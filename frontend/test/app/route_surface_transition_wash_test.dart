// 推入路由的过渡期遮蔽：路由表面按策略留透明（`utilitySurface.visible`），
// 而导航栈要到动画结束才把下一页置为 offstage，于是整段过渡都在把上一页
// （以及同一帧正在下滑关闭的账户面板）从新页面底下透出来——这就是"透明过渡"。
// 修复口径是一层随动画退场的实底洗色：两页重合的前程保持全厚，只剩窄缝时才
// 线性放开，落位后完全撤除，终态像素与原实现一致，壁纸照常透上来。
// 全程按比例衰减的旧口径挡不住重合段：动画过半时遮蔽已薄到能透出上一页，
// 抽屉点设置的"页面重叠"就是这么来的。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/route/app_route_surface.dart';
import 'package:omninest/app/router.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/backdrop/domain/app_backdrop_policy.dart';

/// 遮蔽采样步长：一帧的时长，把平台决定的转场拆成可数的帧。
const _frame = Duration(milliseconds: 16);

Future<void> _pumpStack(
  WidgetTester tester, {
  required Size surface,
  required Widget pushed,
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  late NavigatorState navigator;
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: OmniNestTheme.light(),
        home: Builder(
          builder: (context) {
            navigator = Navigator.of(context);
            return const Scaffold(body: Center(child: Text('UNDER')));
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final page = buildAppRoutePage(
    key: const ValueKey('pushed-route'),
    child: pushed,
  );
  navigator.push(page.createRoute(navigator.context));
}

/// 路由表面这一层里正在画的遮蔽色；没有遮蔽层时返回 null。
Color? _wash(WidgetTester tester) {
  final boxes = find.descendant(
    of: find.byType(RouteEnvironmentSurface),
    matching: find.byType(ColoredBox),
  );
  if (boxes.evaluate().isEmpty) {
    return null;
  }
  expect(boxes, findsOneWidget, reason: '遮蔽层必须是唯一的 ColoredBox');
  final color = tester.widget<ColoredBox>(boxes).color;
  return color.a == 0 ? null : color;
}

/// 逐帧采两段行程：遮蔽保持全厚的帧数，以及随后放开到撤除的帧数。
///
/// 转场总时长由平台的 pageTransitionsTheme 决定，测试里不断言绝对毫秒，
/// 只比较这两段的相对长度：全厚段必须不短于放开段。
Future<(int held, int released)> _sampleCoverage(WidgetTester tester) async {
  var heldFrames = 0;
  while (true) {
    await tester.pump(_frame);
    final wash = _wash(tester);
    if (wash == null || wash.a < 1.0) {
      break;
    }
    heldFrames++;
    expect(heldFrames, lessThan(80), reason: '遮蔽全程都不放');
  }
  var releasedFrames = 0;
  while (_wash(tester) != null) {
    await tester.pump(_frame);
    releasedFrames++;
    expect(releasedFrames, lessThan(80), reason: '落位后遮蔽仍未撤除');
  }
  return (heldFrames, releasedFrames);
}

void main() {
  testWidgets('环境可见的路由：起始帧遮住上一页，落位后恢复透明', (tester) async {
    await _pumpStack(
      tester,
      surface: const Size(390, 844),
      pushed: AppRouteSurface.environmental(
        owner: 'route:/profile',
        routePath: '/profile',
        child: const Center(child: Text('PUSHED')),
      ),
    );
    // 路由条目要等下一帧才挂进树，所以推进 16ms 再取起始帧。
    // 路由条目先在下一帧挂树，再随动画推进；所以要 pump 两次。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.text('UNDER'), findsOneWidget, reason: '动画里下一页仍在绘');
    final start = _wash(tester);
    expect(start, isNotNull, reason: '过渡期没有遮蔽层，上一页会从新页面底下透出');
    expect(start!.a, greaterThan(0.9), reason: '起始帧必须接近完全不透明');

    final (heldFrames, releasedFrames) = await _sampleCoverage(tester);
    expect(
      heldFrames,
      greaterThanOrEqualTo(releasedFrames),
      reason: '遮蔽至少要撑到动画过半；重合段薄一层，上一页就透成双重曝光',
    );

    await tester.pumpAndSettle();

    expect(find.text('UNDER'), findsNothing);
    expect(_wash(tester), isNull, reason: '结束后必须完全透明，否则壁纸再也透不上来');
  });

  testWidgets('退出动画同样遮住正在出现的下一页', (tester) async {
    await _pumpStack(
      tester,
      surface: const Size(390, 844),
      pushed: AppRouteSurface.environmental(
        owner: 'route:/profile',
        routePath: '/profile',
        child: const Center(child: Text('PUSHED')),
      ),
    );
    await tester.pumpAndSettle();
    final navigator = tester.state<NavigatorState>(
      find.byType(Navigator).first,
    );
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(_wash(tester), isNotNull, reason: '离场页面若不遮蔽，正在绘制的下一页会双重曝光');
    expect(_wash(tester)!.a, 1.0, reason: '退场起始帧离场页仍铺满屏幕，必须全厚压住下一页');

    final (heldFrames, releasedFrames) = await _sampleCoverage(tester);
    expect(
      heldFrames,
      greaterThanOrEqualTo(releasedFrames),
      reason: '退场也要撑到只剩窄缝才放开遮蔽',
    );
    await tester.pumpAndSettle();
  });

  testWidgets('策略不要求环境可见的路由保持原有实底', (tester) async {
    await _pumpStack(
      tester,
      surface: const Size(1440, 900),
      pushed: AppRouteSurface(
        owner: 'route:/work',
        policy: AppBackdropPolicy.work,
        routePath: '/work',
        child: const Center(child: Text('PUSHED')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(
      _wash(tester),
      Theme.of(
        tester.element(find.byType(RouteEnvironmentSurface)),
      ).colorScheme.surface,
      reason: '不可见策略本来就画实底，不该被洗色路径接管',
    );
  });
}
