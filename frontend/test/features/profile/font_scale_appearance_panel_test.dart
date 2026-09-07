import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/appearance/application/font_scale_controller.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/features/profile/presentation/widgets/profile_appearance_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('外观面板切换字体档位并回写当前选择', (tester) async {
    var current = FontScalePreset.followSystem;
    FontScalePreset? changed;

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            theme: OmniNestTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('zh'),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ProfileAppearancePanel(
                  themeMode: ThemeMode.system,
                  languageCode: 'zh',
                  fontScalePreset: current,
                  onThemeChanged: (_) {},
                  onLanguageChanged: (_) {},
                  onFontScaleChanged: (preset) {
                    changed = preset;
                    setState(() => current = preset);
                  },
                  onBackdropSettings: () {},
                ),
              ),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('字体大小'), findsOneWidget);
    expect(find.text('跟随系统'), findsWidgets);

    await tester.tap(find.text('舒适'));
    await tester.pumpAndSettle();

    expect(changed, FontScalePreset.comfortable);
  });
}
