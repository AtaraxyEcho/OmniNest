import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_image_budget_notice.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 摘要：钉住图片降级提示的显示条件与关闭回调，防止"未知计数"被当成缺图。
void main() {
  group('shouldShowImageBudgetNotice', () {
    test('计数未知或为零时不提示', () {
      expect(shouldShowImageBudgetNotice(null), isFalse);
      expect(shouldShowImageBudgetNotice(0), isFalse);
    });

    test('计数为正时提示', () {
      expect(shouldShowImageBudgetNotice(1), isTrue);
      expect(shouldShowImageBudgetNotice(42), isTrue);
    });
  });

  testWidgets('提示显示张数并可通过关闭按钮退出', (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderImageBudgetNotice(
            count: 3,
            settings: ReaderViewSettings(),
            label: '3 张图片未加载',
            hint: '本章图片超出单章容量上限，正文不受影响',
            dismissTooltip: '关闭',
            onDismiss: () => dismissed++,
          ),
        ),
      ),
    );

    expect(find.text('3 张图片未加载'), findsOne);
    expect(find.text('本章图片超出单章容量上限，正文不受影响'), findsOne);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(dismissed, 1);
  });

  testWidgets('关闭按钮满足移动端触控下限', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderImageBudgetNotice(
            count: 1,
            settings: ReaderViewSettings(),
            label: '1 张图片未加载',
            hint: '说明',
            dismissTooltip: '关闭',
            onDismiss: () {},
          ),
        ),
      ),
    );

    final box = tester.getSize(find.byType(IconButton));
    expect(box.height, greaterThanOrEqualTo(48));
    expect(box.width, greaterThanOrEqualTo(48));
  });
}
