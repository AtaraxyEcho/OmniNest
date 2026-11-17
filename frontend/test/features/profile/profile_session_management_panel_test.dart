import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/profile/application/profile_controller.dart';
import 'package:omninest/features/profile/domain/user_session.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_session_management_panel.dart';

void main() {
  testWidgets('重进会话管理面板时刷新会话列表', (tester) async {
    var builds = 0;
    final container = ProviderContainer.test(
      overrides: [
        userSessionsProvider.overrideWith((ref) async {
          builds += 1;
          return const [];
        }),
      ],
    );
    addTearDown(container.dispose);

    Widget host() => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: OmniNestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(
          body: ProfileSessionManagementPanel(framed: false),
        ),
      ),
    );

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(builds, 1);

    await tester.pumpWidget(
      KeyedSubtree(key: const ValueKey('revisit'), child: host()),
    );
    await tester.pumpAndSettle();

    expect(builds, 2);
  });

  // 两行种子：当前会话（徽章）与非当前会话（占位），时间取当前时刻
  // 保证同年紧凑格式稳定。
  List<UserSession> seedSessions() {
    final now = DateTime.now();
    String iso(DateTime time) => time.toIso8601String();
    return [
      UserSession(
        id: 'session-current',
        clientPlatform: 'WEB',
        ipAddress: '192.168.1.50',
        issuedAt: iso(now.subtract(const Duration(hours: 2))),
        expiresAt: iso(now.add(const Duration(days: 29))),
        lastActiveAt: iso(now),
        createdAt: iso(now.subtract(const Duration(days: 1))),
        deviceName: 'Chrome · Windows',
        current: true,
      ),
      UserSession(
        id: 'session-other',
        clientPlatform: 'ANDROID',
        ipAddress: '10.0.0.8',
        issuedAt: iso(now.subtract(const Duration(days: 5))),
        expiresAt: iso(now.add(const Duration(days: 25))),
        lastActiveAt: iso(now.subtract(const Duration(hours: 8))),
        createdAt: iso(now.subtract(const Duration(days: 5))),
        deviceName: 'Pixel 8',
        current: false,
      ),
    ];
  }

  Widget sessionHost() {
    return ProviderScope(
      overrides: [
        userSessionsProvider.overrideWith((ref) async => seedSessions()),
      ],
      child: MaterialApp(
        theme: OmniNestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(
          body: ProfileSessionManagementPanel(framed: false),
        ),
      ),
    );
  }

  testWidgets('宽视口全列铺开：IP 独立成列且状态徽章不铺满列宽', (tester) async {
    tester.view.physicalSize = const Size(1400, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(sessionHost());
    await tester.pumpAndSettle();

    // 七列表头齐备。
    expect(find.text('设备 / 浏览器'), findsOneWidget);
    expect(find.text('IP 地址'), findsOneWidget);
    expect(find.text('登录时间'), findsOneWidget);
    expect(find.text('有效期'), findsOneWidget);
    expect(find.text('最后活跃'), findsOneWidget);
    expect(find.text('状态'), findsOneWidget);
    // IP 独立 cell 展示，不再与登录时间拼接在同一文本。
    expect(find.text('192.168.1.50'), findsOneWidget);
    expect(find.textContaining('192.168.1.50 ·'), findsNothing);
    expect(find.text('10.0.0.8'), findsOneWidget);
    // 当前会话徽章按内容收缩：宽度必须小于状态列 100px。
    final badge = tester.renderObject<RenderBox>(find.text('当前会话'));
    expect(badge.size.width, lessThan(100), reason: '徽章不得铺满状态列');
    // 非当前会话状态列占位。
    expect(find.text('—'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('中档视口隐藏有效期与最后活跃明细列', (tester) async {
    tester.view.physicalSize = const Size(900, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(sessionHost());
    await tester.pumpAndSettle();

    expect(find.text('登录时间'), findsOneWidget);
    expect(find.text('有效期'), findsNothing);
    expect(find.text('最后活跃'), findsNothing);
    expect(find.text('192.168.1.50'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄视口降级卡片流合并 IP 与登录时间', (tester) async {
    tester.view.physicalSize = const Size(600, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(sessionHost());
    await tester.pumpAndSettle();

    // 无表头；卡片内 IP 与登录时间合并为一行，有效期另起一行。
    expect(find.text('IP 地址'), findsNothing);
    expect(find.textContaining('192.168.1.50 ·'), findsOneWidget);
    expect(find.textContaining('有效期至'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
