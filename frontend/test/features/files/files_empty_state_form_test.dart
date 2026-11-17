// 文件列表空态分形态：托管态走环境玻璃空态，桌面保留工位描边框。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/app_theme_palette.dart';
import 'package:omninest/core/widgets/env_empty_state.dart';
import 'package:omninest/core/widgets/mobile_shell_scope.dart';
import 'package:omninest/features/files/presentation/widgets/file_node_actions.dart';

Future<void> _pump(WidgetTester tester, {required bool hosted}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      theme: OmniNestTheme.from(AppThemePalette.dark),
      home: Scaffold(
        body: MobileShellScope(
          hosted: hosted,
          child: const Center(
            child: FileNodeEmptyState(showingRecycleBin: false),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('托管态空态不再画工位直角描边框', (tester) async {
    await _pump(tester, hosted: true);

    expect(find.byType(EnvEmptyState), findsOneWidget);
    expect(find.text('暂无文件'), findsOneWidget);
    final framed =
        tester
            .widgetList<Container>(find.byType(Container))
            .where(
              (widget) =>
                  (widget.decoration as BoxDecoration?)?.border != null &&
                  (widget.decoration as BoxDecoration?)?.color == null,
            )
            .toList();
    expect(framed, isEmpty, reason: '环境皮肤空态不带描边框盒子');
  });

  testWidgets('桌面态仍用工位描边框空态', (tester) async {
    await _pump(tester, hosted: false);

    expect(find.byType(EnvEmptyState), findsNothing);
    expect(find.text('暂无文件'), findsOneWidget);
  });
}
