import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/appearance/application/font_scale_controller.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_appearance_panel.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_desktop_shell.dart';

void main() {
  testWidgets('个人中心外观面板承接原设置页的主题和语言职责', (tester) async {
    ThemeMode? selectedTheme;
    String? selectedLanguage;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: OmniNestTheme.light(),
        home: Scaffold(
          body: ProfileAppearancePanel(
            themeMode: ThemeMode.system,
            languageCode: 'zh',
            fontScalePreset: FontScalePreset.followSystem,
            onThemeChanged: (value) => selectedTheme = value,
            onLanguageChanged: (value) => selectedLanguage = value,
            onFontScaleChanged: (_) {},
            onBackdropSettings: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('浅色模式'));
    await tester.pump();
    await tester.tap(find.text('English'));
    await tester.pump();

    expect(selectedTheme, ThemeMode.light);
    expect(selectedLanguage, 'en');
    expect(find.text('管理背景'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面个人中心侧栏在紧凑窗口保持稳定并提供退出入口', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 680));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ProfileSection? selectedSection;
    var signedOut = false;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: OmniNestTheme.light(),
        home: ProfileDesktopShell(
          selectedSection: ProfileSection.account,
          onSectionSelected: (value) => selectedSection = value,
          displayName: '名称较长的超级管理员账户',
          username: 'administrator-with-long-name',
          role: 'SUPER_ADMIN',
          avatarUrl: null,
          onBack: () {},
          onNotifications: () {},
          onSignOut: () => signedOut = true,
          child: const SizedBox(height: 560),
        ),
      ),
    );

    await tester.tap(find.text('外观与语言'));
    await tester.tap(find.text('退出登录'));
    await tester.pump();

    expect(selectedSection, ProfileSection.appearance);
    expect(signedOut, isTrue);
    expect(tester.takeException(), isNull);
  });
}
