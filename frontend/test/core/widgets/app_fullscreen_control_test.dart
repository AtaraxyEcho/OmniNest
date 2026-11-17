import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/widgets/app_fullscreen_control.dart';

void main() {
  testWidgets('全屏按钮同步图标、提示和点击状态', (tester) async {
    var isFullscreen = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: StatefulBuilder(
          builder: (context, setState) {
            return Center(
              child: AppFullscreenButton(
                isFullscreen: isFullscreen,
                foregroundColor: Colors.white,
                accentColor: Colors.cyan,
                onPressed: () => setState(() => isFullscreen = !isFullscreen),
              ),
            );
          },
        ),
      ),
    );

    expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
    expect(find.byTooltip('全屏（F11）'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.fullscreen_rounded));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.fullscreen_exit_rounded), findsOneWidget);
    expect(find.byTooltip('退出全屏（F11）'), findsOneWidget);
  });

  testWidgets('自定义提示覆盖默认 F11 全屏文案', (tester) async {
    var isFullscreen = false;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('zh'),
        home: StatefulBuilder(
          builder: (context, setState) {
            return Center(
              child: AppFullscreenButton(
                isFullscreen: isFullscreen,
                foregroundColor: Colors.white,
                accentColor: Colors.cyan,
                enterTooltip: '沉浸模式',
                exitTooltip: '退出沉浸模式',
                onPressed: () => setState(() => isFullscreen = !isFullscreen),
              ),
            );
          },
        ),
      ),
    );

    expect(find.byTooltip('沉浸模式'), findsOneWidget);
    expect(find.byTooltip('全屏（F11）'), findsNothing);

    await tester.tap(find.byIcon(Icons.fullscreen_rounded));
    await tester.pumpAndSettle();

    expect(find.byTooltip('退出沉浸模式'), findsOneWidget);
    expect(find.byTooltip('退出全屏（F11）'), findsNothing);
  });
}
