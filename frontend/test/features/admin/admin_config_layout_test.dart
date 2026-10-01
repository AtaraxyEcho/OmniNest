import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/presentation/pages/admin_operations_pages.dart';

/// 双分组测试数据：TMDB 2 项 + 存储与共享空间 2 项，用于分组计数断言。
const _groupedView = AdminConfigManagementView(
  items: [
    AdminConfigEntry(
      key: 'media.tmdb.enabled',
      value: 'true',
      valueType: 'BOOLEAN',
      category: 'media',
      refreshScope: 'HOT',
      updatedAt: '2026-09-29T08:00:00Z',
      surface: 'INTEGRATION',
      displayCode: 'config.integration.tmdb.enabled',
    ),
    AdminConfigEntry(
      key: 'media.tmdb.url',
      value: 'https://api.example.test/3',
      valueType: 'STRING',
      category: 'media',
      refreshScope: 'HOT',
      updatedAt: '2026-09-29T08:00:00Z',
      surface: 'INTEGRATION',
      displayCode: 'config.integration.tmdb.baseUrl',
    ),
    AdminConfigEntry(
      key: 'share.max-bytes',
      value: '0',
      valueType: 'NUMBER',
      category: 'storage',
      refreshScope: 'HOT',
      updatedAt: '2026-09-29T08:00:00Z',
      surface: 'GENERAL',
      displayCode: 'config.storage.sharedSpaceLimit',
    ),
    AdminConfigEntry(
      key: 'storage.quota.default',
      value: '10',
      valueType: 'NUMBER',
      category: 'storage',
      refreshScope: 'HOT',
      updatedAt: '2026-09-29T08:00:00Z',
      surface: 'GENERAL',
      displayCode: 'config.storage.defaultQuota',
    ),
  ],
);

Future<void> _pumpConfigPage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: OmniNestTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: AdminConfigPage(view: _groupedView),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('配置中心统一单表展示分组列且不展示原始键', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const view = AdminConfigManagementView(
      items: [
        AdminConfigEntry(
          key: 'media.auto-import.enabled',
          value: 'true',
          valueType: 'BOOLEAN',
          category: 'media',
          refreshScope: 'HOT',
          updatedAt: '2026-08-14T08:00:00Z',
          surface: 'GENERAL',
          displayCode: 'config.media.autoImport',
        ),
        AdminConfigEntry(
          key: 'music.metadata-provider.musicbrainz.enabled',
          value: 'false',
          valueType: 'BOOLEAN',
          category: 'music',
          refreshScope: 'HOT',
          updatedAt: '2026-08-14T08:00:00Z',
          surface: 'INTEGRATION',
          displayCode: 'config.integration.musicbrainz.enabled',
        ),
        AdminConfigEntry(
          key: 'media.tmdb.url',
          value: 'https://api.example.test/3',
          valueType: 'STRING',
          category: 'media',
          refreshScope: 'HOT',
          updatedAt: '2026-08-14T08:00:00Z',
          surface: 'INTEGRATION',
          displayCode: 'config.integration.tmdb.baseUrl',
        ),
        AdminConfigEntry(
          key: 'media.metadata-providers.enabled',
          value: 'true',
          valueType: 'BOOLEAN',
          category: 'media',
          refreshScope: 'HOT',
          updatedAt: '2026-08-14T08:00:00Z',
          surface: 'GENERAL',
          displayCode: 'config.media.metadataProviders',
        ),
        AdminConfigEntry(
          key: 'share.max-bytes',
          value: '0',
          valueType: 'NUMBER',
          category: 'storage',
          refreshScope: 'HOT',
          updatedAt: '2026-08-14T08:00:00Z',
          surface: 'GENERAL',
          displayCode: 'config.storage.sharedSpaceLimit',
        ),
        AdminConfigEntry(
          key: 'storage.quota.default',
          value: '10',
          valueType: 'NUMBER',
          category: 'storage',
          refreshScope: 'HOT',
          updatedAt: '2026-08-14T08:00:00Z',
          surface: 'GENERAL',
          displayCode: 'config.storage.defaultQuota',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: OmniNestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(
            body: SingleChildScrollView(child: AdminConfigPage(view: view)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('系统设置'), findsNothing);
    expect(find.text('集成服务'), findsNothing);
    expect(find.text('自动导入已发现的媒体'), findsOneWidget);
    expect(find.text('media.auto-import.enabled'), findsNothing);
    expect(find.text('媒体元数据服务'), findsNothing);
    expect(find.text('共享空间容量上限'), findsOneWidget);
    expect(find.textContaining('无限制'), findsNWidgets(3));
    expect(find.textContaining('10.0 GB'), findsOneWidget);
    expect(find.text('启用 MusicBrainz'), findsOneWidget);
    expect(find.text('TMDB 服务地址'), findsOneWidget);
    expect(
      find.text('music.metadata-provider.musicbrainz.enabled'),
      findsNothing,
    );

    // 关闭态下拉不渲染菜单项：'MusicBrainz' 仅出现在分组单元格；
    // '存储与共享空间' 出现在两行分组单元格。
    expect(find.text('MusicBrainz'), findsOneWidget);
    expect(find.text('存储与共享空间'), findsNWidgets(2));
    expect(find.text('分组'), findsWidgets);
    // 每页条数选择器：分页条内紧凑下拉（MenuAnchor 触发钮），默认 10。
    final pageSizeSelector = find.byType(MenuAnchor).evaluate().toList();
    expect(pageSizeSelector, hasLength(1));
    expect(
      find.descendant(of: find.byType(MenuAnchor), matching: find.text('10')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('背景库大小配置按 MB 展示而非原始字节', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const view = AdminConfigManagementView(
      items: [
        AdminConfigEntry(
          key: 'backdrop.max-image-bytes',
          value: '20971520',
          valueType: 'NUMBER',
          category: 'backdrop',
          refreshScope: 'HOT',
          updatedAt: '2026-09-22T08:00:00Z',
          surface: 'GENERAL',
          displayCode: 'config.backdrop.maxImageBytes',
        ),
        AdminConfigEntry(
          key: 'backdrop.max-video-bytes',
          value: '469762048',
          valueType: 'NUMBER',
          category: 'backdrop',
          refreshScope: 'HOT',
          updatedAt: '2026-09-22T08:00:00Z',
          surface: 'GENERAL',
          displayCode: 'config.backdrop.maxVideoBytes',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: OmniNestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(
            body: SingleChildScrollView(child: AdminConfigPage(view: view)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('20.0 MB'), findsOneWidget);
    expect(find.textContaining('448.0 MB'), findsOneWidget);
    // 原始字节不得再出现在列表里。
    expect(find.textContaining('20971520'), findsNothing);
    expect(find.textContaining('469762048'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('分组筛选下拉过滤配置列表', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const view = AdminConfigManagementView(
      items: [
        AdminConfigEntry(
          key: 'media.auto-import.enabled',
          value: 'true',
          valueType: 'BOOLEAN',
          category: 'media',
          refreshScope: 'HOT',
          updatedAt: '2026-08-14T08:00:00Z',
          surface: 'GENERAL',
          displayCode: 'config.media.autoImport',
        ),
        AdminConfigEntry(
          key: 'storage.quota.default',
          value: '10',
          valueType: 'NUMBER',
          category: 'storage',
          refreshScope: 'HOT',
          updatedAt: '2026-08-14T08:00:00Z',
          surface: 'GENERAL',
          displayCode: 'config.storage.defaultQuota',
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: OmniNestTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: const Scaffold(
            body: SingleChildScrollView(child: AdminConfigPage(view: view)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 工位皮肤：分组筛选改为直角 chips，直接点按目标分组 chip。
    await tester.tap(
      find.descendant(
        of: find.byType(FilterChip),
        matching: find.textContaining('存储与共享空间'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('自动导入已发现的媒体'), findsNothing);
    expect(find.text('新用户默认配额'), findsOneWidget);
  });

  testWidgets('分组筛选 chips 首帧即显示真实分组计数且无 0 计数', (tester) async {
    await _pumpConfigPage(tester);

    // 无任何交互：首帧计数直接来自 view.items 全量数据。
    expect(find.text('全部 (4)'), findsOneWidget);
    expect(find.text('TMDB (2)'), findsOneWidget);
    expect(find.text('存储与共享空间 (2)'), findsOneWidget);
    expect(find.textContaining('(0)'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('选中分组后其余分组与全部计数保持真实值', (tester) async {
    await _pumpConfigPage(tester);

    await tester.tap(find.text('TMDB (2)'));
    await tester.pumpAndSettle();

    // 计数是全量纯函数：不随选中分组变为 0 或缩水。
    expect(find.text('全部 (4)'), findsOneWidget);
    expect(find.text('TMDB (2)'), findsOneWidget);
    expect(find.text('存储与共享空间 (2)'), findsOneWidget);
    expect(find.textContaining('(0)'), findsNothing);
    // 筛选语义不变：仅 TMDB 行可见。
    expect(find.text('TMDB 服务地址'), findsOneWidget);
    expect(find.text('新用户默认配额'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无匹配搜索时全部计数不归零', (tester) async {
    await _pumpConfigPage(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AdminConfigPage)),
      listen: false,
    );
    container.read(adminSearchProvider.notifier).updateQuery('zzz-no-match');
    await tester.pumpAndSettle();

    // 搜索只收敛表格：chips 计数保持全量真实值。
    expect(find.text('全部 (4)'), findsOneWidget);
    expect(find.text('TMDB (2)'), findsOneWidget);
    expect(find.text('存储与共享空间 (2)'), findsOneWidget);
    expect(find.textContaining('(0)'), findsNothing);
    expect(find.text('TMDB 服务地址'), findsNothing);
    expect(find.text('新用户默认配额'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
