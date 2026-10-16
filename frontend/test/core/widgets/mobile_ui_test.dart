import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/env_empty_state.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';
import 'package:omninest/core/widgets/omni_icons.dart';

void main() {
  testWidgets('移动端分段控件在窄屏下保持稳定并响应选择', (tester) async {
    var selected = 0;
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              builder:
                  (context, setState) => MobileSegmentedControl<int>(
                    values: const [0, 1, 2],
                    selected: selected,
                    labelBuilder: (value) => '选项 ${value + 1}',
                    onSelected: (value) => setState(() => selected = value),
                  ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.tap(find.text('选项 3'));
    await tester.pumpAndSettle();

    expect(selected, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('分段控件的读屏节点名称只播一次且用 tab 的选中态', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileSegmentedControl<int>(
            values: const [0, 1],
            selected: 1,
            labelBuilder: (value) => '选项 ${value + 1}',
            onSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final selectedNode = tester.getSemantics(find.text('选项 2')).toString();
    final plainNode = tester.getSemantics(find.text('选项 1')).toString();

    expect(selectedNode, contains('isSelected'));
    expect(
      selectedNode,
      isNot(contains('isChecked')),
      reason: '样例 .segmented 是 tablist，用 aria-selected 不用 aria-checked',
    );
    expect(selectedNode, contains('label: "选项 2"'));
    expect(
      selectedNode,
      isNot(contains(r'选项 2\n选项 2')),
      reason: 'Semantics 与子级 Text 同写 label 会让段名播两遍',
    );
    expect(plainNode, isNot(contains('isSelected')));
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('移动空态族支持 1.3 倍文字缩放', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: EnvEmptyState(
              icon: OmniIcons.library,
              title: '还没有内容',
              message: '网络暂时不可用，恢复连接后可以继续同步当前内容。',
              actionLabel: '重新加载',
              onAction: () {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('重新加载'), findsOneWidget);
  });
}
