import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_scrolling_input.dart';

void main() {
  group('ReaderScrollInputAdapter（方案 §89/§137）', () {
    test('滚轮/触控板/拖动/键盘归一为输入源上抛', () {
      final sources = <ReaderScrollInputSource>[];
      final adapter = ReaderScrollInputAdapter(onInput: sources.add);

      adapter.pointerScroll();
      adapter.dragThresholdCrossed();
      adapter.keyboardScroll();

      expect(sources, const [
        ReaderScrollInputSource.mouseWheel,
        ReaderScrollInputSource.pointerDrag,
        ReaderScrollInputSource.keyboard,
      ]);
    });
  });
}
