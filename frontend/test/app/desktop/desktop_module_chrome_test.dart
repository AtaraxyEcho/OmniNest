import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/desktop/widgets/desktop_section_bar.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/desktop/desktop_theme.dart';
import 'package:omninest/core/widgets/desktop_chrome_only.dart';
import 'package:omninest/core/widgets/desktop_shell_scope.dart';

Widget _host(Widget child, {required bool hosted}) {
  return MediaQuery(
    data: const MediaQueryData(size: Size(1400, 900)),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: DesktopTheme.resolve(isDark: true),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: DesktopShellScope(hosted: hosted, child: Scaffold(body: child)),
    ),
  );
}

void main() {
  testWidgets('未托管时模块自带控件照常渲染', (tester) async {
    await tester.pumpWidget(
      _host(
        const DesktopChromeOnly(child: Text('module-avatar')),
        hosted: false,
      ),
    );
    expect(find.text('module-avatar'), findsOneWidget);
  });

  testWidgets('桌面壳托管时模块自带的重复全局控件让位', (tester) async {
    await tester.pumpWidget(
      _host(
        const DesktopChromeOnly(child: Text('module-avatar')),
        hosted: true,
      ),
    );
    expect(find.text('module-avatar'), findsNothing);
  });

  testWidgets('作用域缺省视为未托管，移动端与独立页面不受影响', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) =>
                  Text('hosted=${DesktopShellScope.isHosted(context)}'),
        ),
      ),
    );
    expect(find.text('hosted=false'), findsOneWidget);
  });

  testWidgets('分区条渲染全部分区并把切换回传给模块', (tester) async {
    String selected = 'Films';
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder:
              (context, setState) => DesktopSectionBar<String>(
                options: const ['Films', 'Series', 'Anime'],
                value: selected,
                labelOf: (value) => value,
                onChanged: (value) => setState(() => selected = value),
              ),
        ),
        hosted: true,
      ),
    );

    expect(find.text('Films'), findsOneWidget);
    expect(find.text('Series'), findsOneWidget);
    expect(find.text('Anime'), findsOneWidget);

    await tester.tap(find.text('Series'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(selected, 'Series');
  });
}
