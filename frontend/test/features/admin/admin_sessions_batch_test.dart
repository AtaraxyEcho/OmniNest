import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/data/admin_operations_api.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/domain/admin_paging.dart';
import 'package:omninest/features/admin/presentation/pages/admin_operations_pages.dart';

class _MockAdminOperationsApi extends Mock implements AdminOperationsApi {}

AdminSessionItem _session({
  required String id,
  String? revokedAt,
  String? revokeReason,
  String clientPlatform = 'web',
}) {
  return AdminSessionItem(
    id: id,
    userId: 'u-$id',
    username: 'user-$id',
    clientPlatform: clientPlatform,
    ipAddress: '10.0.0.1',
    issuedAt: '2026-08-30T08:00:00Z',
    expiresAt: '2027-09-30T08:00:00Z',
    lastActiveAt: '2026-09-01T08:00:00Z',
    revokedAt: revokedAt,
    revokeReason: revokeReason,
  );
}

const _sessionQuery = (
  page: 0,
  size: 10,
  status: 'ALL',
  platform: 'ALL',
  query: '',
  sort: 'lastActiveAt',
  dir: 'desc',
);

Future<void> _pumpSessionsPage(
  WidgetTester tester, {
  required List<AdminSessionItem> items,
  AdminOperationsApi? api,
  int? cleanupPreviewCount,
}) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        adminSessionPageProvider(_sessionQuery).overrideWith(
          (ref) async => AdminPage<AdminSessionItem>(
            items: items,
            page: 0,
            size: 10,
            totalElements: items.length,
            totalPages: 1,
          ),
        ),
        if (api != null) adminOperationsApiProvider.overrideWithValue(api),
        if (cleanupPreviewCount != null)
          adminCleanupPreviewProvider((
            kind: AdminCleanupPreviewKind.sessions,
            retentionDays: 30,
          )).overrideWith((ref) async => cleanupPreviewCount),
      ],
      child: MaterialApp(
        theme: OmniNestTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: Scaffold(body: const AdminSessionsPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('会话页勾选活跃会话出现批量操作条且禁用已吊销行', (tester) async {
    await _pumpSessionsPage(
      tester,
      items: [
        _session(id: 'active-1'),
        _session(id: 'revoked-1', revokedAt: '2026-09-01T09:00:00Z'),
      ],
    );

    expect(find.text('user-active-1'), findsOneWidget);
    expect(find.text('user-revoked-1'), findsOneWidget);
    expect(find.text('批量强制下线'), findsNothing);

    // 三颗复选框：表头全选 + 两行；第二行为已吊销会话，不可勾选。
    final checkboxes = find.byType(Checkbox);
    expect(checkboxes, findsNWidgets(3));
    await tester.tap(checkboxes.at(2));
    await tester.pump();
    expect(find.text('批量强制下线'), findsNothing, reason: '已吊销行不可勾选');

    await tester.tap(checkboxes.at(1));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);
    expect(find.text('批量强制下线'), findsOneWidget);
  });

  testWidgets('指标卡统计活跃吊销过期并按平台归类客户端分布', (tester) async {
    final expired = AdminSessionItem(
      id: 'expired-1',
      userId: 'u-expired-1',
      username: 'user-expired-1',
      clientPlatform: 'android',
      ipAddress: '10.0.0.2',
      issuedAt: '2026-08-01T08:00:00Z',
      expiresAt: '2026-08-02T08:00:00Z',
      lastActiveAt: '2026-08-01T08:00:00Z',
    );

    await _pumpSessionsPage(
      tester,
      items: [
        _session(id: 'active-1'),
        _session(id: 'pc-1', clientPlatform: 'windows'),
        expired,
        _session(id: 'revoked-1', revokedAt: '2026-09-01T09:00:00Z'),
      ],
    );

    expect(find.text('已吊销'), findsOneWidget);
    // “已过期”出现在指标卡标题与过期会话状态标签（详情弹窗等组件
    // 复用同一文案，精确计数随列布局演进脆弱，断言下限）。
    expect(find.text('已过期'), findsAtLeastNWidgets(2));
    expect(find.text('客户端分布'), findsOneWidget);
    // MiniStat 以 RichText 拼接“计数 + 标签”：Web 2 / PC 1 / 移动端 1。
    Finder miniStatText(String plainText) {
      return find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText() == plainText,
      );
    }

    expect(miniStatText('2 Web'), findsOneWidget);
    expect(miniStatText('1 PC'), findsOneWidget);
    expect(miniStatText('1 移动端'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('会话详情按钮打开工位弹窗并展示吊销原因块', (tester) async {
    await _pumpSessionsPage(
      tester,
      items: [
        _session(id: 'active-1'),
        _session(
          id: 'revoked-1',
          revokedAt: '2026-09-01T09:00:00Z',
          revokeReason: '管理员清理异常登录',
        ),
      ],
    );

    final detailButtons = find.byIcon(Icons.info_outlined);
    expect(detailButtons, findsNWidgets(2));
    await tester.tap(detailButtons.at(1));
    await tester.pumpAndSettle();

    expect(find.byType(WorkstationDialogFrame), findsOneWidget);
    expect(find.text('会话详情'), findsOneWidget);
    // “设备 ID”两处：列表新增的设备 ID 列头 + 会话详情弹窗键值行。
    expect(find.text('设备 ID'), findsNWidgets(2));
    expect(find.text('管理员清理异常登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('会话清理弹窗展示预估条数与在线会话说明', (tester) async {
    await _pumpSessionsPage(
      tester,
      items: [_session(id: 'active-1')],
      cleanupPreviewCount: 7,
    );

    await tester.tap(find.text('清理'));
    await tester.pumpAndSettle();

    expect(find.byType(WorkstationDialogFrame), findsOneWidget);
    expect(find.text('预估清理'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.textContaining('在线会话不受影响'), findsOneWidget);
    expect(find.textContaining('物理删除'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('单个强制下线经工位破坏性确认后调用接口', (tester) async {
    final api = _MockAdminOperationsApi();
    when(() => api.revokeSession('active-1')).thenAnswer((_) async {});

    await _pumpSessionsPage(
      tester,
      items: [_session(id: 'active-1')],
      api: api,
    );

    // 行内踢出按钮是唯一的 logout_outlined；指标卡用 rounded 家族不冲突。
    await tester.tap(find.byIcon(Icons.logout_outlined));
    await tester.pumpAndSettle();
    expect(find.byType(WorkstationDialogFrame), findsOneWidget);
    // 确认文案包含目标设备（clientPlatform 兜底）。
    expect(find.text('确定要撤销该会话吗？设备: web'), findsOneWidget);

    await tester.tap(find.text('踢出会话'));
    await tester.pumpAndSettle();

    verify(() => api.revokeSession('active-1')).called(1);
    expect(tester.takeException(), isNull);
  });
}
