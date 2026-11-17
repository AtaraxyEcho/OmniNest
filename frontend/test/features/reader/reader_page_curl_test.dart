import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_page_view.dart';

/// 造一张带边距块的「纸面」，用来分辨正反两面与卷曲方向。
Future<ui.Image> _pageImage(Color paper, Color block) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 400, 600), Paint()..color = paper);
  canvas.drawRect(const Rect.fromLTWH(40, 80, 320, 90), Paint()..color = block);
  canvas.drawRect(
    const Rect.fromLTWH(40, 240, 240, 16),
    Paint()..color = block.withValues(alpha: 0.5),
  );
  return recorder.endRecording().toImage(400, 600);
}

Future<void> _pumpCurl(
  WidgetTester tester, {
  required double progress,
  required ui.Image front,
  required ui.Image back,
}) async {
  tester.view.physicalSize = const Size(400, 600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 400,
          height: 600,
          child: ReaderPageCurl(
            front: front,
            back: back,
            progress: progress,
            paper: const Color(0xFFF6F1E4),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('卷页在各个进度都能画出 28 片条带且不抛异常', (tester) async {
    final front = await tester.runAsync(
      () => _pageImage(const Color(0xFFF6F1E4), const Color(0xFF4A6A8A)),
    );
    final back = await tester.runAsync(
      () => _pageImage(const Color(0xFFEFE8D6), const Color(0xFF8A6A4A)),
    );
    expect(front, isNotNull);
    expect(back, isNotNull);

    for (final progress in [0.05, 0.25, 0.5, 0.75, 0.95]) {
      await _pumpCurl(tester, progress: progress, front: front!, back: back!);
      expect(tester.takeException(), isNull, reason: 'p=$progress');
      expect(find.byType(CustomPaint), findsWidgets, reason: 'p=$progress');
    }
  });

  testWidgets('进度为 0 时卷页贴合纸面，不出现折痕', (tester) async {
    final front = await tester.runAsync(
      () => _pageImage(const Color(0xFFF6F1E4), const Color(0xFF4A6A8A)),
    );
    final back = await tester.runAsync(
      () => _pageImage(const Color(0xFFEFE8D6), const Color(0xFF8A6A4A)),
    );
    await _pumpCurl(tester, progress: 0, front: front!, back: back!);
    expect(tester.takeException(), isNull);
  });
}
