import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/feedback/omni_feedback.dart';
import 'package:toastification/toastification.dart';

Widget _host(Widget child) {
  return ToastificationWrapper(
    config: omniFeedbackToastConfig,
    child: MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh'), Locale('en')],
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

/// 条目经 post-frame 回调挂入 AnimatedList，且入场动画需要时间推进，
/// 两次空帧加一段时长推进后才可见。
Future<void> _show(WidgetTester tester, String message) async {
  await tester.tap(find.byKey(ValueKey('trigger-$message')));
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

/// 冲刷自动关闭计时器与移除动画，避免测试结束残留 pending timer。
Future<void> _flush(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 10));
  await tester.pumpAndSettle();
}

Widget _trigger(
  String message, {
  OmniFeedbackSeverity severity = OmniFeedbackSeverity.info,
}) {
  return Builder(
    builder:
        (context) => TextButton(
          key: ValueKey('trigger-$message'),
          onPressed:
              () => showOmniFeedback(context, message, severity: severity),
          child: Text('触发-$message'),
        ),
  );
}

void main() {
  // toastification 为全局单例，manager 持有已销毁树的 overlayEntry 时会
  // 跳过 holder 重建，导致后续测试的条目永不渲染；每个用例前清空。
  setUp(() {
    toastification.managers.clear();
  });

  testWidgets('按 info 分级时长自动消失', (tester) async {
    await tester.pumpWidget(_host(_trigger('已复制')));
    await _show(tester, '已复制');
    expect(find.text('已复制'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('已复制'), findsNothing);
  });

  testWidgets('error 分级停留时间长于 info', (tester) async {
    await tester.pumpWidget(
      _host(_trigger('操作失败', severity: OmniFeedbackSeverity.error)),
    );
    await _show(tester, '操作失败');
    // info 默认 2 秒已消失的时点，error（4 秒）仍应可见。
    await tester.pump(const Duration(seconds: 2, milliseconds: 400));
    expect(find.text('操作失败'), findsOneWidget);
    await _flush(tester);
  });

  testWidgets('同文案合并为一条并重置计时', (tester) async {
    await tester.pumpWidget(_host(_trigger('已保存')));
    await _show(tester, '已保存');
    await tester.pump(const Duration(seconds: 1));
    await _show(tester, '已保存');
    // 旧条移除与新条重挂存在一个空窗期，需要额外 settle。
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('已保存'), findsOneWidget);
    await _flush(tester);
  });

  testWidgets('不同文案可并存且超出上限淘汰最旧', (tester) async {
    await tester.pumpWidget(
      _host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final message in ['第一条', '第二条', '第三条', '第四条'])
              _trigger(message),
          ],
        ),
      ),
    );
    await _show(tester, '第一条');
    await _show(tester, '第二条');
    await _show(tester, '第三条');
    expect(find.text('第一条'), findsOneWidget);
    expect(find.text('第三条'), findsOneWidget);
    await _show(tester, '第四条');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('第一条'), findsNothing);
    expect(find.text('第四条'), findsOneWidget);
    await _flush(tester);
  });

  testWidgets('动作按钮渲染在文案下方并回调', (tester) async {
    var fired = false;
    await tester.pumpWidget(
      _host(
        Builder(
          builder:
              (context) => TextButton(
                key: const ValueKey('trigger-action'),
                onPressed:
                    () => showOmniFeedback(
                      context,
                      '已移入回收站',
                      actionLabel: '撤销',
                      onAction: () => fired = true,
                    ),
                child: const Text('触发动作'),
              ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('trigger-action')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('已移入回收站'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await tester.pump();
    expect(fired, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('已移入回收站'), findsNothing);
  });

  testWidgets('showOmniError 走错误码本地化链路', (tester) async {
    await tester.pumpWidget(
      _host(
        Builder(
          builder:
              (context) => TextButton(
                key: const ValueKey('trigger-error'),
                onPressed:
                    () => showOmniError(
                      context,
                      const AppException(code: 'NETWORK_ERROR', message: 'raw'),
                    ),
                child: const Text('触发错误'),
              ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('trigger-error')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    final l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    expect(find.text(l10n.errorNetworkError), findsOneWidget);
    expect(find.text('raw'), findsNothing);
    await _flush(tester);
  });

  testWidgets('unmounted 上下文调用安全返回', (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    showOmniFeedback(captured, '不应出现');
    await tester.pump();
    expect(find.text('不应出现'), findsNothing);
  });
}
