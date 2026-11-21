import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/widgets/desktop_error_boundary.dart';

import 'desktop_test_harness.dart';

/// 只在第一次 build 抛错：重挂后再建就正常，用来验证「重试」真的重挂子树。
class _BoomOnce extends StatefulWidget {
  const _BoomOnce();

  static int attempts = 0;

  @override
  State<_BoomOnce> createState() => _BoomOnceState();
}

class _BoomOnceState extends State<_BoomOnce> {
  @override
  Widget build(BuildContext context) {
    _BoomOnce.attempts++;
    if (_BoomOnce.attempts == 1) {
      throw StateError('build failed');
    }
    return const Text('recovered');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('子树 build 抛错时就地变成 .route-err，重试能重挂内容', (tester) async {
    _BoomOnce.attempts = 0;
    await tester.pumpWidget(
      wrapDesktop(
        const Center(child: DesktopErrorBoundary(child: _BoomOnce())),
      ),
    );
    await tester.pump();

    // 框架仍会把这次 build 错误报给测试进程，先消费掉再断言界面。
    expect(tester.takeException(), isA<StateError>());
    expect(find.text('Something went wrong on this page.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('recovered'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('recovered'), findsOneWidget);
    expect(find.text('Something went wrong on this page.'), findsNothing);
  });

  testWidgets('接管只在构建帧内生效，帧末把 ErrorWidget.builder 还原', (tester) async {
    final original = ErrorWidget.builder;
    await tester.pumpWidget(
      wrapDesktop(const Center(child: DesktopErrorBoundary(child: Text('ok')))),
    );
    await tester.pump();

    expect(find.text('ok'), findsOneWidget);
    // 帧后回调已跑，全局构造器必须回到调用前的样子，否则会污染移动端。
    expect(ErrorWidget.builder, same(original));
  });

  testWidgets('路由切换期间顶部扫 2px 进度条', (tester) async {
    await tester.pumpWidget(
      wrapDesktop(
        const Center(
          child: DesktopRouteContainer(
            path: '/x',
            loading: true,
            child: Text('page'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(DesktopRouteProgressBar), findsOneWidget);
    expect(tester.getSize(find.byType(DesktopRouteProgressBar)).height, 2);
    expect(find.text('page'), findsOneWidget);

    await tester.pumpWidget(
      wrapDesktop(
        const Center(
          child: DesktopRouteContainer(
            path: '/x',
            loading: false,
            child: Text('page'),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(DesktopRouteProgressBar), findsNothing);
  });
}
