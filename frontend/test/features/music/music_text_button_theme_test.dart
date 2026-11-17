import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/feature/music_backdrop_theme.dart';

/// Music 模块文字按钮中性前景契约：模块内 TextButton（查看全部、重试、
/// 对话框次要动作等）不得回落 colorScheme.primary（模块语境下为深绿）。
void main() {
  testWidgets('模块主题下文字按钮前景为中性次级色而非 primary', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: MusicBackdropTheme.withNeutralTextButtons(OmniNestTheme.light()),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: const Scaffold(
          body: Center(child: TextButton(onPressed: null, child: Text('占位'))),
        ),
      ),
    );
    // 直接校验主题层样式，避免禁用态/合并态对渲染色的干扰。
    final theme = Theme.of(tester.element(find.text('占位')));
    final foreground = theme.textButtonTheme.style?.foregroundColor;
    expect(foreground?.resolve({}), theme.colorScheme.onSurfaceVariant);
    expect(foreground?.resolve({}), isNot(theme.colorScheme.primary));
  });
}
