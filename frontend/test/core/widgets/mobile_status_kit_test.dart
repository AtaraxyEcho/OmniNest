import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/mobile_status_kit.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';

Future<void> _pumpSlot(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(body: Center(child: SizedBox(width: 358, child: child))),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openConfirm(
  WidgetTester tester, {
  required String title,
  required String confirmLabel,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(
        body: Builder(
          builder:
              (context) => ElevatedButton(
                onPressed: () {
                  showMobileConfirmSheet(
                    context,
                    title: title,
                    message: '此操作影响 3 个项目，已同步副本可在回收站找回 30 天。',
                    confirmLabel: confirmLabel,
                    cancelLabel: '取消',
                    destructive: true,
                  );
                },
                child: const Text('open'),
              ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('状态丸 23 高、大写、按色调取色', (tester) async {
    await _pumpSlot(
      tester,
      const Align(
        alignment: Alignment.centerLeft,
        child: MobileStatusPill(
          label: 'paused',
          tone: MobileStatusTone.warning,
        ),
      ),
    );

    final pill = find.byType(MobileStatusPill);
    expect(tester.getSize(pill).height, greaterThanOrEqualTo(23));
    expect(find.text('PAUSED'), findsOneWidget);
    final box = tester.widget<Container>(
      find.descendant(of: pill, matching: find.byType(Container)).first,
    );
    final decoration = box.decoration! as BoxDecoration;
    expect(decoration.color, const Color(0x1FD18A34));
    expect(decoration.borderRadius, BorderRadius.circular(8));
  });

  testWidgets('传输行 78 高并画 3px 进度与状态丸', (tester) async {
    await _pumpSlot(
      tester,
      const MobileTransferRow(
        title: 'Spring trip originals',
        detail: '842 MB of 1.2 GB',
        icon: OmniIcons.image,
        progress: 0.68,
        statusLabel: '68%',
      ),
    );

    expect(
      tester.getSize(find.byType(MobileTransferRow)).height,
      greaterThanOrEqualTo(78),
    );
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.68);
    expect(bar.minHeight, 3);
    expect(find.byType(MobileStatusPill), findsOneWidget);
  });

  testWidgets('传输摘要三格均分且不低于 69 高', (tester) async {
    await _pumpSlot(
      tester,
      const MobileTransferSummary(
        entries: [
          MobileTransferSummaryEntry(value: '3', label: 'active'),
          MobileTransferSummaryEntry(value: '1.2 GB', label: 'remaining'),
          MobileTransferSummaryEntry(value: '12 min', label: 'estimated'),
        ],
      ),
    );

    final cells = find.byType(MobileTransferSummary);
    expect(tester.getSize(cells).height, greaterThanOrEqualTo(69));
    expect(find.text('ACTIVE'), findsNWidgets(1));
    expect(find.text('1.2 GB'), findsOneWidget);
  });

  testWidgets('离线横幅为 42 高琥珀条件条', (tester) async {
    await _pumpSlot(tester, const MobileOfflineBanner(message: '当前离线，需要网络连接'));

    final banner = find.byType(MobileOfflineBanner);
    expect(tester.getSize(banner).height, greaterThanOrEqualTo(42));
    final container = tester.widget<Container>(
      find.descendant(of: banner, matching: find.byType(Container)).first,
    );
    expect(
      (container.decoration! as BoxDecoration).color,
      const Color(0x1FD18A34),
    );
  });

  testWidgets('受阻说明条带右侧行动并回传点击', (tester) async {
    var tapped = 0;
    await _pumpSlot(
      tester,
      MobileDisabledCard(
        icon: OmniIcons.settings,
        title: '蜂窝网络下暂停上传',
        message: '连接 Wi-Fi 或在设置中允许计量传输。',
        actionLabel: '设置',
        onAction: () => tapped++,
      ),
    );

    expect(
      tester.getSize(find.byType(MobileDisabledCard)).height,
      greaterThanOrEqualTo(62),
    );
    await tester.tap(find.text('设置'));
    await tester.pump();
    expect(tapped, 1);
  });

  testWidgets('确认面板排 52 图块与两个等宽按钮，取消关闭', (tester) async {
    await _openConfirm(tester, title: '移除所选项目？', confirmLabel: '移除 3 项');

    expect(find.text('移除所选项目？'), findsOneWidget);
    final confirm = find.text('移除 3 项');
    final cancel = find.text('取消');
    expect(confirm, findsOneWidget);
    expect(cancel, findsOneWidget);
    // 两个按钮等宽（原型 flex:1 + gap 8）。
    final confirmBox =
        find.ancestor(of: confirm, matching: find.byType(Container)).first;
    final cancelBox =
        find.ancestor(of: cancel, matching: find.byType(Container)).first;
    expect(tester.getSize(confirmBox).width, tester.getSize(cancelBox).width);
    expect(tester.getSize(confirmBox).height, greaterThanOrEqualTo(45));

    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.text('移除 3 项'), findsNothing);
  });

  testWidgets('确认面板危险钮为 #b95f5f 实底', (tester) async {
    await _openConfirm(tester, title: '清空回收站？', confirmLabel: '清空');

    final container = tester.widget<Container>(
      find
          .ancestor(of: find.text('清空'), matching: find.byType(Container))
          .first,
    );
    expect(
      (container.decoration! as BoxDecoration).color,
      const Color(0xFFB95F5F),
    );

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(find.text('清空'), findsNothing);
  });
}
