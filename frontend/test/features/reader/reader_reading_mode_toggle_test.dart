import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';

void main() {
  test('阅读模式在翻页与滚动之间往返切换', () {
    final scroll = ReaderViewSettings(readingMode: 'scroll');
    final page = scroll.withReadingModeToggled();

    expect(page.readingMode, 'page');
    expect(page.withReadingModeToggled().readingMode, 'scroll');
  });

  test('切换阅读模式不得顺带改写其它排版设置', () {
    final settings = ReaderViewSettings(
      readingMode: 'scroll',
      fontSize: 21,
      lineHeight: 1.6,
      pageTurnMode: 'fade',
      immersiveMode: true,
    );

    final toggled = settings.withReadingModeToggled();

    expect(toggled.readingMode, 'page');
    expect(toggled.fontSize, 21);
    expect(toggled.lineHeight, 1.6);
    expect(toggled.pageTurnMode, 'fade');
    expect(toggled.immersiveMode, isTrue);
  });
}
