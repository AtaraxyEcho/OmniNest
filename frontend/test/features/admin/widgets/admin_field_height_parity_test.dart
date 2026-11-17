import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/widgets/app_dropdown.dart';
import 'package:omninest/features/admin/presentation/theme/admin_workstation_theme.dart';

/// 工位域表单高度一致性：AppDropdown 与 TextField（皮肤
/// inputDecorationTheme 驱动）在同一表单内渲染高度必须严格相等。
///
/// 复现“编辑库源 / OAuth 应用”弹窗的字段混排形态：无 helper 时
/// 36（桌面）/ 44（触控），带 helperText 时 46 / 54。
Widget _wrap(Widget child) {
  return MaterialApp(
    theme: OmniNestTheme.light(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: AdminWorkstationScope(child: Center(child: child))),
  );
}

void _runParityChecks(WidgetTester tester) {
  final dropdown = tester.getSize(find.byKey(const Key('dropdown-plain')));
  final dropdownHelper = tester.getSize(
    find.byKey(const Key('dropdown-helper')),
  );
  final textPlain = tester.getSize(find.byKey(const Key('text-plain')));
  final textHelper = tester.getSize(find.byKey(const Key('text-helper')));
  expect(dropdown.height, textPlain.height, reason: '下拉与输入框（无 helper）必须等高');
  expect(
    dropdownHelper.height,
    textHelper.height,
    reason: '下拉与输入框（带 helperText）必须等高',
  );
}

void main() {
  testWidgets('桌面密度：同一表单内下拉与输入框高度一致', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_wrap(_form()));
      await tester.pumpAndSettle();
      _runParityChecks(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('触控密度：同一表单内下拉与输入框高度一致', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_wrap(_form()));
    await tester.pumpAndSettle();
    _runParityChecks(tester);
  });
}

Widget _form() {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: AppDropdown<String>(
              key: const Key('dropdown-plain'),
              value: 'A',
              items: const [AppDropdownItem(value: 'A', label: '类型')],
              onChanged: (_) {},
              label: '类型',
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: TextField(
              key: Key('text-plain'),
              decoration: InputDecoration(labelText: '客户端 ID'),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: AppDropdown<String>(
              key: const Key('dropdown-helper'),
              value: 'A',
              items: const [AppDropdownItem(value: 'A', label: '媒体库类型')],
              onChanged: (_) {},
              label: '媒体库类型',
              helperText: '类型说明',
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: TextField(
              key: Key('text-helper'),
              decoration: InputDecoration(
                labelText: '重定向 URI',
                helperText: '回调说明',
              ),
            ),
          ),
        ],
      ),
    ],
  );
}
