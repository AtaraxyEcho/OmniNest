import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/notifications/presentation/widgets/notification_icon.dart';

class _Unread extends UnreadCountNotifier {
  _Unread(this.value);

  final int value;

  @override
  int build() => value;
}

/// 入口只依赖未读数：故意不覆盖 activeTaskSummaryProvider，组件若再去 watch
/// 任务摘要就会真实发起请求并失败，测试随之变红。
Future<void> _pump(WidgetTester tester, {required int unread}) async {
  // ProviderScope 的 overrides 在挂载后不可变更，重复 pump 前必须先卸载上一棵树。
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [unreadCountProvider.overrideWith(() => _Unread(unread))],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        theme: OmniNestTheme.dark(),
        routerConfig: GoRouter(
          initialLocation: '/host',
          routes: [
            GoRoute(
              path: '/host',
              builder:
                  (context, state) =>
                      const Scaffold(body: Center(child: NotificationIcon())),
            ),
            GoRoute(
              path: '/notifications',
              builder:
                  (context, state) =>
                      const Scaffold(body: Center(child: Text('通知页'))),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('入口打开通知页', (tester) async {
    await _pump(tester, unread: 0);

    await tester.tap(find.byType(NotificationIcon));
    await tester.pumpAndSettle();

    expect(find.text('通知页'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('未读数显示为徽标', (tester) async {
    await _pump(tester, unread: 3);

    expect(find.text('3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无未读时只有铃铛', (tester) async {
    await _pump(tester, unread: 0);

    expect(find.text('3'), findsNothing);
    expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
