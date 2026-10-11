// 分段导航滑动胶囊的行为守卫。
//
// 判三件事：选中胶囊是**滑过去**而不是就地换色（中途必须在两段之间）；
// 连续档按页码插值（媒体库空间的 PageView 跟手）；段数超出可用宽度时
// 横向滚动而不是整体缩放（照片页六档实测曾被压到 54×33）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/widgets/mobile_sliding_segment_row.dart';
import 'package:omninest/core/widgets/mobile_ui.dart';

Finder _pill() => find.byKey(segmentPillKey);

Finder _segmentTap(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byType(InkWell),
);

/// 用受控状态装配分段控件：点按真的改选中，才能判"滑块跟着选中走"。
Future<void> _pumpControl(
  WidgetTester tester, {
  required List<String> labels,
  int initialSelected = 0,
  Size surface = const Size(360, 800),
  bool disableAnimations = false,
  void Function(int value)? onSelected,
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  var selected = initialSelected;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(disableAnimations: disableAnimations),
            child: Scaffold(
              body: StatefulBuilder(
                builder:
                    (context, setState) => MobileSegmentedControl<int>(
                      values: List<int>.generate(labels.length, (i) => i),
                      selected: selected,
                      labelBuilder: (value) => labels[value],
                      onSelected: (value) {
                        setState(() => selected = value);
                        onSelected?.call(value);
                      },
                    ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('切换分段时选中胶囊从旧段滑到新段', (tester) async {
    await _pumpControl(
      tester,
      labels: const ['全部', '照片', '影视'],
    );

    final originLeft = tester.getTopLeft(_pill()).dx;
    expect(
      originLeft,
      closeTo(tester.getTopLeft(_segmentTap('全部')).dx, 0.5),
      reason: '滑块起始应与选中段左沿重合',
    );

    await tester.tap(_segmentTap('影视'));
    // 第一帧只是启动补间，滑块仍在旧段；再走 60ms 才能看到它在段间。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final midwayLeft = tester.getTopLeft(_pill()).dx;
    final targetLeft = tester.getTopLeft(_segmentTap('影视')).dx;
    expect(midwayLeft, lessThan(targetLeft - 0.5));
    expect(midwayLeft, greaterThan(originLeft + 0.5));

    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(_pill()).dx,
      closeTo(targetLeft, 0.5),
      reason: '动画结束后滑块应与新选中段对齐',
    );
    expect(
      tester.getSize(_pill()).width,
      closeTo(tester.getSize(_segmentTap('影视')).width, 0.5),
    );
  });

  testWidgets('段宽按粗体度量，切换字重不改变段的排布', (tester) async {
    await _pumpControl(tester, labels: const ['全部', '收藏剧集']);
    final before = tester.getTopLeft(_segmentTap('收藏剧集')).dx;

    await tester.tap(_segmentTap('收藏剧集'));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(_segmentTap('收藏剧集')).dx,
      closeTo(before, 0.5),
      reason: '选中加粗后段宽若变化，整行会左右抖',
    );
  });

  testWidgets('六档窄屏保持最小段宽并靠横向滚动 reach 尾档', (tester) async {
    var tapped = -1;
    await _pumpControl(
      tester,
      labels: const ['全部', '影集', '收藏', '时间线', '位置', '回收站'],
      surface: const Size(320, 800),
      onSelected: (value) => tapped = value,
    );

    for (final label in const ['全部', '影集', '收藏', '时间线']) {
      final size = tester.getSize(_segmentTap(label));
      expect(size.width, greaterThanOrEqualTo(66));
      expect(size.height, 40);
    }
    // 整行宽出可用视口 → 必须可滚，而不是整体等比缩放。
    expect(
      find.ancestor(
        of: _pill(),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    await tester.dragUntilVisible(
      _segmentTap('回收站'),
      find.byType(SingleChildScrollView),
      const Offset(-60, 0),
    );
    await tester.tap(_segmentTap('回收站'));
    await tester.pumpAndSettle();
    expect(tapped, 5);
    expect(tester.getSize(_segmentTap('回收站')).width, greaterThanOrEqualTo(66));
  });

  testWidgets('减弱动效下切换直接落终态', (tester) async {
    await _pumpControl(
      tester,
      labels: const ['全部', '照片', '影视'],
      disableAnimations: true,
    );

    await tester.tap(_segmentTap('影视'));
    await tester.pump();
    expect(
      tester.getTopLeft(_pill()).dx,
      closeTo(tester.getTopLeft(_segmentTap('影视')).dx, 0.5),
      reason: '减弱动效不应留下一段补间',
    );
  });

  testWidgets('连续档按页码在两档之间插值', (tester) async {
    const labels = ['全部', '照片', '影视', '音乐'];
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MobileSlidingSegmentRow(
            labels: labels,
            selectedIndex: 1,
            page: 1.5,
            onTap: (_) {},
            activeInk: Colors.black,
            idleInk: Colors.grey,
            pill: const BoxDecoration(color: Color(0xFFFF0000)),
          ),
        ),
      ),
    );
    await tester.pump();

    // 页码 1.5 → 滑块应停在第 2、3 段箱体左沿的中点，宽度取两者均值。
    final boxLefts = <double>[
      for (final label in labels) tester.getTopLeft(_segmentTap(label)).dx,
    ];
    final boxWidths = <double>[
      for (final label in labels) tester.getSize(_segmentTap(label)).width,
    ];
    expect(
      tester.getTopLeft(_pill()).dx,
      closeTo((boxLefts[1] + boxLefts[2]) / 2, 0.5),
    );
    expect(
      tester.getSize(_pill()).width,
      closeTo((boxWidths[1] + boxWidths[2]) / 2, 0.5),
    );
  });
}
