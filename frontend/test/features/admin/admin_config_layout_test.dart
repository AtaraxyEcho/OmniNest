import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/presentation/pages/admin_operations_pages.dart';
import 'package:omninest/app/widgets/app_dropdown.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_list_components.dart';

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
    // 每页条数选择器：统一 AppDropdown，默认 10。
    final pageSizeDropdown =
        find
            .byWidgetPredicate((w) => w is AppDropdown<int>)
            .evaluate()
            .toList();
    expect(pageSizeDropdown, hasLength(1));
    expect((pageSizeDropdown.first.widget as AppDropdown<int>).value, 10);
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

    final dropdownField = find.byWidgetPredicate(
      (w) => w is AppDropdown<String>,
    );
    await tester.tap(dropdownField.first);
    await tester.pumpAndSettle();
    // 菜单经 Overlay 浮层渲染，默认 finder 视为 offstage：经 MenuItemButton 定位。
    await tester.tap(
      find.descendant(
        of: find.byType(MenuItemButton),
        matching: find.text('存储与共享空间'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('自动导入已发现的媒体'), findsNothing);
    expect(find.text('新用户默认配额'), findsOneWidget);
  });
}
