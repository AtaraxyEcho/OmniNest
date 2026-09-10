import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/theme/app_theme.dart';
import 'package:omninest/app/theme/control_tokens.dart';
import 'package:omninest/app/widgets/app_dropdown.dart';

void main() {
  testWidgets('dense 下拉与按钮高度对齐', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.light(),
        home: Scaffold(
          body: Column(
            children: [
              const SizedBox(
                width: 180,
                child: AppDropdown<String>(
                  dense: true,
                  label: '状态',
                  value: 'ALL',
                  items: [
                    AppDropdownItem(value: 'ALL', label: '全部'),
                    AppDropdownItem(value: 'ACTIVE', label: '活跃'),
                  ],
                  onChanged: null,
                ),
              ),
              FilledButton(onPressed: () {}, child: const Text('清理')),
            ],
          ),
        ),
      ),
    );

    final dropdownFinder = find.byType(AppDropdown<String>);
    final buttonFinder = find.byType(FilledButton);
    expect(dropdownFinder, findsOneWidget);
    expect(buttonFinder, findsOneWidget);

    final dropdownSize = tester.getSize(dropdownFinder);
    final buttonSize = tester.getSize(buttonFinder);

    // 筛选下拉高度应接近按钮，且不得明显高于按钮。
    expect(
      dropdownSize.height,
      moreOrLessEquals(buttonSize.height, epsilon: 4),
    );
    expect(
      dropdownSize.height,
      moreOrLessEquals(AppControlTokens.buttonHeight, epsilon: 4),
    );
    expect(
      buttonSize.height,
      moreOrLessEquals(AppControlTokens.buttonHeight, epsilon: 4),
    );
  });

  testWidgets('表单下拉使用浮动标签且不低于控件高度', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: OmniNestTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 220,
              child: AppDropdown<String>(
                label: '存储位置',
                value: 'local',
                items: const [
                  AppDropdownItem(value: 'local', label: '本地'),
                  AppDropdownItem(value: 'minio', label: 'MinIO'),
                ],
                onChanged: null,
              ),
            ),
          ),
        ),
      ),
    );

    final size = tester.getSize(find.byType(AppDropdown<String>));
    expect(size.height, greaterThanOrEqualTo(AppControlTokens.fieldHeight));
  });

  test('控件尺寸令牌数值合法', () {
    expect(AppControlTokens.buttonHeight, greaterThanOrEqualTo(36));
    expect(AppControlTokens.fieldHeight, greaterThanOrEqualTo(36));
    expect(
      AppControlTokens.menuItemHeight,
      lessThanOrEqualTo(AppControlTokens.buttonHeight + 8),
    );
    expect(AppControlTokens.controlRadius, 8);
  });
}
