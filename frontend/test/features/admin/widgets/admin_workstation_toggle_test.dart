import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/core/widgets/workstation_controls.dart';
import 'package:omninest/features/admin/presentation/theme/admin_workstation_theme.dart';

Widget _wrap(Widget child, {Brightness brightness = Brightness.dark}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness, useMaterial3: true),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: AdminWorkstationScope(child: Center(child: child))),
  );
}

/// 找到 32×16 轨道容器（组件内以 ValueKey 标记，区别于 10×10 滑块）。
AnimatedContainer _trackOf(WidgetTester tester) {
  return tester.widget<AnimatedContainer>(
    find.byKey(const ValueKey('workstation-toggle-track')),
  );
}

void main() {
  group('WorkstationToggle', () {
    testWidgets('点击轨道取反回传；开关行点击任意位置同样切换', (tester) async {
      bool? standaloneNext;
      bool? rowNext;
      await tester.pumpWidget(
        _wrap(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WorkstationToggle(
                value: false,
                onChanged: (value) => standaloneNext = value,
              ),
              const SizedBox(height: 24),
              WorkstationToggle(
                value: true,
                label: '启用媒体库',
                onChanged: (value) => rowNext = value,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(WorkstationToggle).first);
      expect(standaloneNext, isTrue, reason: '独立开关点击回传取反值');

      // 点击 label 文本（行左端）也应触发整行切换。
      await tester.tap(find.text('启用媒体库'));
      expect(rowNext, isFalse, reason: '开关行点击 label 区域整行切换');
    });

    testWidgets('禁用态不回调且整行 45% 透明', (tester) async {
      var called = 0;
      await tester.pumpWidget(
        _wrap(
          WorkstationToggle(
            value: true,
            label: '扫描后自动入库',
            enabled: false,
            onChanged: (_) => called++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final opacity = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(WorkstationToggle),
          matching: find.byType(Opacity),
        ),
      );
      expect(opacity.opacity, 0.45);

      await tester.tap(find.text('扫描后自动入库'), warnIfMissed: false);
      await tester.tap(find.byType(WorkstationToggle), warnIfMissed: false);
      expect(called, 0, reason: '禁用态点击不产生回调');

      final semantics = tester.widget<Semantics>(
        find
            .descendant(
              of: find.byType(WorkstationToggle),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(semantics.properties.enabled, isFalse);
      expect(semantics.properties.toggled, isTrue);
    });

    testWidgets('选中态轨道 onSurface 反色填充，未选中 surfaceContainerHighest', (
      tester,
    ) async {
      const toggle = Key('toggle');
      late BuildContext captured;
      bool value = true;
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              captured = context;
              return WorkstationToggle(
                key: toggle,
                value: value,
                onChanged:
                    (next) => setState(() {
                      value = next;
                    }),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scheme = Theme.of(captured).colorScheme;
      expect(
        (_trackOf(tester).decoration as BoxDecoration).color,
        scheme.onSurface,
        reason: '选中轨道以 onSurface 反色填充',
      );

      await tester.tap(find.byKey(toggle));
      await tester.pumpAndSettle();
      expect(
        (_trackOf(tester).decoration as BoxDecoration).color,
        scheme.surfaceContainerHighest,
        reason: '未选中轨道回落容器底色',
      );
      expect(
        AdminColors.of(captured).onSurface,
        scheme.onSurface,
        reason: 'Admin 工位皮肤生效',
      );
    });
  });
}
