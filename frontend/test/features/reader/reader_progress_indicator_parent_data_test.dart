import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_progress_indicator.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

/// 摘要：钉住常驻进度控件不自带 `Positioned`。
///
/// 阅读页把它放在 `Stack → Positioned → IgnorePointer → AnimatedOpacity` 链里做交叉淡入。
/// 控件自己返回 `Positioned` 时，`StackParentData` 会挂到 `FadeTransition` 上，
/// 每次重帧都抛 `Incorrect use of ParentDataWidget`，整页渲染失败。
/// 这条断言在旧写法下必红，是那个线上崩溃的最小回归门。
void main() {
  Widget host(Widget indicator) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.black)),
            IgnorePointer(child: indicator),
          ],
        ),
      ),
    );
  }

  testWidgets('胶囊形态嵌在动画链里也不得携带 ParentDataWidget', (tester) async {
    await tester.pumpWidget(
      host(
        ReaderProgressIndicator(
          key: const Key('readerPersistentProgress'),
          settings: ReaderViewSettings(),
          progress: 0.42,
          sampleChrome: false,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('42.0%'), findsOne);
  });

  testWidgets('样例形态同样不携带 ParentDataWidget', (tester) async {
    await tester.pumpWidget(
      host(
        ReaderProgressIndicator(
          settings: ReaderViewSettings(),
          progress: 0.42,
          sampleChrome: true,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(LinearProgressIndicator), findsOne);
  });
}
