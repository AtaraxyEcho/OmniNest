import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_shortcuts.dart';

void main() {
  const resolver = ReaderShortcutResolver();

  test('space follows reading mode and shift direction', () {
    expect(
      resolver.resolve(
        key: LogicalKeyboardKey.space,
        mode: ReaderShortcutMode.textScroll,
      ),
      ReaderCommand.nextViewport,
    );
    expect(
      resolver.resolve(
        key: LogicalKeyboardKey.space,
        mode: ReaderShortcutMode.textPage,
        shiftPressed: true,
      ),
      ReaderCommand.previousPage,
    );
  });

  test('comic horizontal keys follow RTL reading direction', () {
    expect(
      resolver.resolve(
        key: LogicalKeyboardKey.arrowRight,
        mode: ReaderShortcutMode.comicPage,
      ),
      ReaderCommand.nextPage,
    );
    expect(
      resolver.resolve(
        key: LogicalKeyboardKey.arrowRight,
        mode: ReaderShortcutMode.comicPage,
        isRtl: true,
      ),
      ReaderCommand.previousPage,
    );
  });

  test(
    'comic mode ignores text-only commands while keeping shared commands',
    () {
      expect(
        resolver.resolve(
          key: LogicalKeyboardKey.keyB,
          mode: ReaderShortcutMode.comicPage,
        ),
        isNull,
      );
      expect(
        resolver.resolve(
          key: LogicalKeyboardKey.keyN,
          mode: ReaderShortcutMode.comicScroll,
        ),
        isNull,
      );
      expect(
        resolver.resolve(
          key: LogicalKeyboardKey.keyT,
          mode: ReaderShortcutMode.comicScroll,
        ),
        ReaderCommand.toggleContents,
      );
    },
  );

  test('text input focus only allows escape to close a layer', () {
    expect(
      resolver.resolve(
        key: LogicalKeyboardKey.space,
        mode: ReaderShortcutMode.textScroll,
        textInputFocused: true,
      ),
      isNull,
    );
    expect(
      resolver.resolve(
        key: LogicalKeyboardKey.escape,
        mode: ReaderShortcutMode.textScroll,
        textInputFocused: true,
      ),
      ReaderCommand.closeLayer,
    );
  });

  test('F11 不映射阅读器命令，交由 app 级全局无边框全屏', () {
    expect(
      resolver.resolve(
        key: LogicalKeyboardKey.f11,
        mode: ReaderShortcutMode.textPage,
      ),
      isNull,
    );
    expect(
      resolver.resolve(
        key: LogicalKeyboardKey.f11,
        mode: ReaderShortcutMode.comicPage,
      ),
      isNull,
    );
  });

  test('command gate rejects repeated discrete commands', () {
    final gate = ReaderCommandGate();
    final start = DateTime(2026, 7, 30, 12);
    expect(gate.accept(start), isTrue);
    expect(gate.accept(start.add(const Duration(milliseconds: 100))), isFalse);
    expect(gate.accept(start.add(const Duration(milliseconds: 230))), isTrue);
  });
}
