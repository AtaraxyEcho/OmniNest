import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_theme.dart';
import 'package:omninest/core/widgets/desktop_shell_scope.dart';
import 'package:omninest/features/video/application/movie_center_state.dart';
import 'package:omninest/features/video/presentation/widgets/movie_shell.dart';

import 'desktop_test_harness.dart';

/// 模块在桌面统一壳内的托管形态验收：
/// 模块自己的顶栏与分区侧栏让位，分区改走页内分段条，内容照常渲染。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpShell(WidgetTester tester, {required bool hosted}) async {
    tester.view.physicalSize = kDesktopViewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: desktopSeedOverrides(),
        child: MediaQuery(
          data: const MediaQueryData(size: kDesktopViewport),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: DesktopTheme.resolve(isDark: true),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: DesktopShellScope(
              hosted: hosted,
              child: MovieShell(
                section: MovieSection.movies,
                childFor: (section) => Text('body:${section.name}'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
  }

  testWidgets('未托管：影视模块保留自己的分区侧栏', (tester) async {
    await pumpShell(tester, hosted: false);

    expect(find.byType(MovieSidebar), findsOneWidget);
    expect(find.text('body:movies'), findsOneWidget);
  });

  testWidgets('桌面壳托管：侧栏让位，分区改走页内分段条，内容不变', (tester) async {
    await pumpShell(tester, hosted: true);

    expect(tester.takeException(), isNull);
    expect(find.byType(MovieSidebar), findsNothing);
    expect(find.text('body:movies'), findsOneWidget);
    // 分区仍然可达，只是换了承载形式。
    expect(find.text('TV Shows'), findsOneWidget);
    expect(find.text('Anime'), findsOneWidget);
    expect(find.text('Favorites'), findsOneWidget);
  });
}
