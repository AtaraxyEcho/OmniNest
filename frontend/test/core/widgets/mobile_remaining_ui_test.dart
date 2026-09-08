import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/appearance/application/font_scale_controller.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/features/admin/domain/admin_section.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_shell.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/presentation/pages/file_preview_page.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_mobile_content.dart';

void main() {
  const targetSizes = <Size>[
    Size(360, 800),
    Size(412, 915),
    Size(700, 400),
    Size(840, 1180),
  ];

  testWidgets('个人中心在目标移动尺寸和放大字体下不溢出', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in targetSizes) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        _testApp(
          ProfileMobileContent(
            displayName: 'OmniNest User With A Long Display Name',
            username: 'long-mobile-account-name',
            email: 'mobile-user@example.com',
            role: 'ADMIN',
            unreadCount: 12,
            weatherCity: 'Shanghai',
            themeMode: ThemeMode.system,
            languageCode: 'zh',
            fontScalePreset: FontScalePreset.followSystem,
            onThemeChanged: (_) {},
            onLanguageChanged: (_) {},
            onFontScaleChanged: (_) {},
            onEditAvatar: _noop,
            onEditWeatherCity: _noop,
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '尺寸 $size 出现布局异常');
    }
  });

  testWidgets('文件预览和管理壳层在窄屏不加载原生媒体插件', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final file = FileNode(
      id: 'file-1',
      parentId: null,
      name: 'unsupported-file.bin',
      isFolder: false,
      nodeType: 'FILE',
      normalizedPath: '/unsupported-file.bin',
      sizeBytes: 1024,
      updatedAt: DateTime(2026, 7, 14),
      mimeType: 'application/x-omninest-test',
    );
    await tester.pumpWidget(_testApp(FilePreviewPage(file: file)));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      _testApp(
        const AdminShell(
          section: AdminSection.overview,
          child: Text('Admin content'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Admin content'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}

Widget _testApp(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      theme: OmniNestTheme.from(AppThemePalette.dark),
      builder:
          (context, appChild) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: appChild!,
          ),
      home: Scaffold(body: child),
    ),
  );
}
