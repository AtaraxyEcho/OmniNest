import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/realtime_providers.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/core/auth/user_capabilities.dart';
import 'package:omninest/core/widgets/workstation_dialog.dart';
import 'package:omninest/features/files/application/file_browser_controller.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_repository.dart';
import 'package:omninest/features/files/presentation/pages/file_browser_page.dart';
import 'package:omninest/features/files/presentation/pages/file_preview_page.dart';
import 'package:omninest/features/files/presentation/widgets/files_table_view.dart';
import 'package:omninest/features/files/presentation/widgets/file_node_actions.dart';

/// 文件模块弹窗全量审计：每个桌面弹窗走「开启 → 尺寸有界（非全屏）→
/// 提交或 Esc 关闭 → 退场动画完成后无任何框架异常」全链路。
///
/// 回归背景：① showWorkstationDialog 的 builder 产物缺少居中松弛层，
/// 路由紧约束把 WorkstationDialogFrame 压成整屏宽（“重命名是全屏模式”）；
/// ② 命名对话框曾在 pop 瞬间 dispose TextEditingController，退场动画期间
/// 组件仍在树上，触发 disposed-controller 与 Overlay 断言级联。
///
/// 仓储用 mocktail 桩：控制器动作多为 extension 方法（静态分发），
/// 子类假体拦不住，必须在仓储层短路网络。
class _MockFileRepository extends Mock implements FileRepository {
  @override
  Future<FileMediaInfo> mediaInfo(String fileId) async => const FileMediaInfo();
}

const _seedFile = FileNode(
  id: 'file-1',
  parentId: null,
  name: 'notes.txt',
  isFolder: false,
  nodeType: 'FILE',
  normalizedPath: '/notes.txt',
  sizeBytes: 1024,
  mimeType: 'text/plain',
  updatedAt: null,
);

const _seedStats = FileStorageStats(
  totalFiles: 1,
  totalFolders: 0,
  usedBytes: 1024,
  quotaBytes: -1,
  quotaStatus: 'UNLIMITED',
  typeDistribution: <FileTypeStats>[],
);

void main() {
  late ProviderContainer container;
  late _MockFileRepository repository;

  Widget host({Locale locale = const Locale('zh')}) {
    final router = GoRouter(
      initialLocation: '/files',
      routes: [
        GoRoute(
          path: '/files',
          builder: (context, state) => const FileBrowserPage(),
        ),
        GoRoute(
          path: '/portal',
          builder:
              (context, state) =>
                  const SizedBox(key: Key('portal-destination')),
        ),
      ],
    );
    addTearDown(router.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: OmniNestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: locale,
      ),
    );
  }

  void stubRepository() {
    when(() => repository.listFilesPage()).thenAnswer(
      (_) async => const FileNodePage(
        items: <FileNode>[_seedFile],
        page: 0,
        size: 50,
        totalElements: 1,
        totalPages: 1,
      ),
    );
    when(() => repository.storageStats()).thenAnswer((_) async => _seedStats);
    when(
      () => repository.listUploadQueue(),
    ).thenAnswer((_) async => const <FileUploadQueueItem>[]);
    when(
      () => repository.renameFile(
        fileId: any(named: 'fileId'),
        name: any(named: 'name'),
      ),
    ).thenAnswer((_) async => _seedFile);
    when(() => repository.deleteFile(any())).thenAnswer((_) async {});
    when(
      () => repository.loadTextPreview(any()),
    ).thenAnswer((_) async => 'preview content');
  }

  Future<void> pumpDesktop(
    WidgetTester tester, {
    Size surface = const Size(1440, 900),
    Locale locale = const Locale('zh'),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = surface;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    repository = _MockFileRepository();
    stubRepository();
    container = ProviderContainer(
      overrides: [
        fileRepositoryProvider.overrideWithValue(repository),
        // 侧栏实时状态点依赖协调器（会拉起 drift/网络），测试态置空。
        realtimeCoordinatorProvider.overrideWith((ref) => null),
        // 匿名会话默认拒绝收藏能力，行内星标不会渲染。
        userCapabilitiesProvider.overrideWithValue(
          const UserCapabilities(
            canBrowseContent: true,
            canContributeContent: true,
            canManageOwnActivity: true,
            canManagePreferences: true,
            canManageAccount: true,
            canUseBackdropLibrary: true,
            canUploadBackdrop: true,
            canViewOwnTasks: true,
            canAdminTasks: false,
            canManageMediaLibrary: false,
            canManagePhotos: false,
            canAdminUsers: false,
            canReadSystemConfig: false,
            canManageSystemConfig: false,
            canAccessAdminConsole: false,
            canSharedBrowse: true,
            canSharedUpload: true,
            canReadWeather: false,
            canReportLocation: false,
            canManageTwoFactor: false,
            canReadActivity: true,
          ),
        ),
      ],
    );
    addTearDown(() => container.dispose());
    await tester.pumpWidget(host(locale: locale));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '页面基线渲染无异常');
    expect(find.text('notes.txt'), findsOneWidget);
  }

  /// 断言当前唯一弹窗容器尺寸有界：宽度不超过声明的 [maxWidth]，且
  /// 远小于视口（1440×900），杜绝任何“全屏弹窗”回归。
  void expectDialogBounded(WidgetTester tester, {double maxWidth = 480}) {
    final frame = find.byType(WorkstationDialogFrame);
    expect(frame, findsOneWidget, reason: '弹窗容器在场');
    final size = tester.getSize(frame);
    expect(size.width, lessThanOrEqualTo(maxWidth), reason: '弹窗宽度不得超宽屏声明值');
    expect(size.width, lessThan(1000), reason: '弹窗不得铺满 1440 视口');
    expect(size.height, lessThan(860), reason: '弹窗不得铺满视口高度');
  }

  Future<void> openRowMenu(WidgetTester tester) async {
    // 行上注册了双击识别器，单击菜单钮需 300ms 消歧后才触发。
    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  testWidgets('重命名：480 有界弹窗，提交与 Esc 关闭后退场无异常', (tester) async {
    await pumpDesktop(tester);

    // ── 提交链路 ──
    await openRowMenu(tester);
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    expectDialogBounded(tester);
    await tester.enterText(
      find.descendant(
        of: find.byType(WorkstationDialogFrame),
        matching: find.byType(TextField),
      ),
      'renamed.txt',
    );
    await tester.tap(find.byType(FilledButton));
    // pop 瞬间 Future 完成，但退场动画与控制器 dispose 尚未结束——
    // 此窗口期正是旧缺陷（disposed controller + 焦点陷阱祖先查询）引爆点。
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '提交关闭链路无框架异常');
    expect(find.byType(WorkstationDialogFrame), findsNothing);
    verify(
      () => repository.renameFile(fileId: 'file-1', name: 'renamed.txt'),
    ).called(1);

    // ── Esc 链路（同一对话框复用控制器生命周期）──
    await openRowMenu(tester);
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    expectDialogBounded(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'Esc 关闭链路无框架异常');
    expect(find.byType(WorkstationDialogFrame), findsNothing);
    // 冲刷反馈条计时器，避免用例结束残留 pending timer。
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });

  testWidgets('点击遮罩可关闭弹窗（模糊层不吞点击）', (tester) async {
    await pumpDesktop(tester);

    await openRowMenu(tester);
    await tester.tap(find.text('重命名'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkstationDialogFrame), findsOneWidget);
    // 点击远离弹窗的左上角遮罩区域。
    await tester.tapAt(const Offset(20, 20));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      find.byType(WorkstationDialogFrame),
      findsNothing,
      reason: '遮罩点击应触发挥示关闭',
    );
  });

  testWidgets('删除：确认弹窗有界，确认后干净关闭', (tester) async {
    await pumpDesktop(tester);

    await openRowMenu(tester);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expectDialogBounded(tester);
    expect(find.byType(FilledButton), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '删除确认链路无框架异常');
    verify(() => repository.deleteFile('file-1')).called(1);
    // 冲刷反馈条计时器，避免用例结束残留 pending timer。
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });

  testWidgets('分享面板：520 有界弹窗，Esc 关闭退场无异常', (tester) async {
    await pumpDesktop(tester);

    await tester.tap(find.byIcon(Icons.share_outlined).first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expectDialogBounded(tester, maxWidth: 520);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '分享面板关闭链路无框架异常');
    expect(find.byType(WorkstationDialogFrame), findsNothing);
  });

  testWidgets('预览弹窗：Esc 直接关闭，全屏切换尺寸正确', (tester) async {
    await pumpDesktop(tester);

    await tester.tap(find.byIcon(Icons.visibility_outlined).first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 紧凑头部：全屏与关闭钮不重叠，钮尺寸不超 32px（旧 AppBar 返回钮
    // 过大/悬浮钮与大小文本重叠的回归锚点）。
    final fullscreenRect = tester.getRect(
      find.byIcon(Icons.open_in_full_rounded),
    );
    final closeRect = tester.getRect(find.byIcon(Icons.close_rounded));
    expect(closeRect.left, greaterThanOrEqualTo(fullscreenRect.right));
    expect(closeRect.width, lessThanOrEqualTo(32));
    expect(fullscreenRect.height, lessThanOrEqualTo(32));
    final previewContainer =
        find
            .descendant(
              of: find.byWidgetPredicate(
                (widget) =>
                    widget.runtimeType.toString() == '_FilePreviewDialog',
              ),
              matching: find.byType(AnimatedContainer),
            )
            .first;
    var size = tester.getSize(previewContainer);
    expect(size.width, closeTo(1440 * 0.86, 2), reason: '常规形态 86vw');
    expect(size.height, closeTo(900 * 0.88, 2), reason: '常规形态 88vh');

    await tester.tap(find.byIcon(Icons.open_in_full_rounded));
    await tester.pumpAndSettle();
    size = tester.getSize(previewContainer);
    expect(size.width, closeTo(1440, 1), reason: '全屏形态铺满视口');
    expect(size.height, closeTo(900, 1));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '预览 Esc 关闭无异常');
    expect(find.byType(FilePreviewPage), findsNothing);
  });

  testWidgets('Inspector dock 自适应：1280 隐藏改贴底抽屉，1500 常驻', (tester) async {
    await pumpDesktop(tester, surface: const Size(1280, 900));
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_InspectorDock',
      ),
      findsNothing,
      reason: '中窄宽度不渲染常驻 dock',
    );
    expect(
      find.byIcon(Icons.view_sidebar_outlined),
      findsNothing,
      reason: '无 dock 可切时隐藏工具条切换钮',
    );

    await pumpDesktop(tester, surface: const Size(1500, 900));
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_InspectorDock',
      ),
      findsOneWidget,
      reason: '宽屏恢复常驻 dock',
    );
    expect(find.byIcon(Icons.view_sidebar_outlined), findsAtLeastNWidgets(1));
  });

  testWidgets('收藏乐观更新：星标在服务器确认前即时翻转', (tester) async {
    await pumpDesktop(tester);
    // 仓储桩挂起：确认乐观路径不等待网络。
    final store = <String>{};
    final gate = Completer<void>();
    when(() => repository.listFavoriteFiles()).thenAnswer(
      (_) async => store.contains('file-1') ? [_seedFile] : const <FileNode>[],
    );
    when(() => repository.addFavorite(any())).thenAnswer((_) async {
      await gate.future;
      store.add('file-1');
      return _seedFile;
    });

    final outline = find.descendant(
      of: find.byType(FileTableView),
      matching: find.byIcon(Icons.star_border_rounded),
    );
    await tester.tap(outline);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle(const Duration(milliseconds: 50));

    // 仓储调用仍挂起，但星标已转实心（乐观发射完成）。
    expect(
      find.descendant(
        of: find.byType(FileTableView),
        matching: find.byIcon(Icons.star_rounded),
      ),
      findsOneWidget,
      reason: '乐观更新不等服务器往返',
    );
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // 收藏成功提示的计时器需要冲刷，避免用例结束残留 pending timer。
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });

  testWidgets('收藏切换走静默快操作：不触发 busy 门控闪烁', (tester) async {
    await pumpDesktop(tester);
    final store = <String>{};
    when(() => repository.listFavoriteFiles()).thenAnswer(
      (_) async => store.contains('file-1') ? [_seedFile] : const <FileNode>[],
    );
    when(() => repository.addFavorite(any())).thenAnswer((invocation) async {
      store.add(invocation.positionalArguments[0] as String);
      return _seedFile;
    });
    // 拦截状态发射：收藏动作期间 isBusy 必须恒为 false（无 0→1→0 闪烁）。
    final busySpikes = <bool>[];
    container.listen(
      fileBrowserControllerProvider.select(
        (async) => async.asData?.value.isBusy,
      ),
      (_, next) => busySpikes.add(next ?? false),
    );

    final outline = find.descendant(
      of: find.byType(FileTableView),
      matching: find.byIcon(Icons.star_border_rounded),
    );
    await tester.tap(outline);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    verify(() => repository.addFavorite('file-1')).called(1);
    expect(busySpikes, isEmpty, reason: '快操作不得进入 busy 态闪禁用');
    // 收藏成功提示的计时器需要冲刷，避免用例结束残留 pending timer。
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });

  testWidgets('英文语言下侧栏与分段控件不溢出', (tester) async {
    await pumpDesktop(tester, locale: const Locale('en'));
    expect(tester.takeException(), isNull, reason: '英文长文案不得触发行溢出');
    expect(find.text('OmniNest Files'), findsOneWidget);
    // 空间分段钮标签在英文下更长，必须仍在树中且无断言。
    expect(find.textContaining('Personal'), findsAtLeastNWidgets(1));
    expect(find.textContaining('Shared'), findsAtLeastNWidgets(1));
  });

  testWidgets('收藏星标双向切换：未收藏点=添加，已收藏点=取消', (tester) async {
    await pumpDesktop(tester);
    // 有状态收藏桩：toggle 后的缓存刷新链必须能看到状态迁移。
    final store = <String>{};
    when(() => repository.listFavoriteFiles()).thenAnswer(
      (_) async => store.contains('file-1') ? [_seedFile] : const <FileNode>[],
    );
    when(() => repository.addFavorite(any())).thenAnswer((invocation) async {
      store.add(invocation.positionalArguments[0] as String);
      return _seedFile;
    });
    when(() => repository.removeFavorite(any())).thenAnswer((invocation) async {
      store.remove(invocation.positionalArguments[0] as String);
    });

    final outline = find.descendant(
      of: find.byType(FileTableView),
      matching: find.byIcon(Icons.star_border_rounded),
    );
    expect(outline, findsOneWidget, reason: '初始未收藏为描边星');
    await tester.tap(outline);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    verify(() => repository.addFavorite('file-1')).called(1);

    // 收藏缓存刷新后行内星标转实心；再次点击必须走取消收藏。
    final filled = find.descendant(
      of: find.byType(FileTableView),
      matching: find.byIcon(Icons.star_rounded),
    );
    expect(filled, findsOneWidget, reason: '已收藏为实心琥珀星');
    await tester.tap(filled);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '取消收藏链路无异常');
    verify(() => repository.removeFavorite('file-1')).called(1);
    expect(outline, findsOneWidget, reason: '取消后星标回到描边态');
    // 收藏成功提示的计时器需要冲刷，避免用例结束残留 pending timer。
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
  });

  testWidgets('新建文件夹为就地草稿行（非弹窗），Esc 取消无异常', (tester) async {
    await pumpDesktop(tester);

    await tester.tap(find.text('新建文件夹'));
    await tester.pumpAndSettle();
    expect(find.byType(FileDraftFolderRow), findsOneWidget, reason: '就地草稿输入行');
    expect(find.byType(WorkstationDialogFrame), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
