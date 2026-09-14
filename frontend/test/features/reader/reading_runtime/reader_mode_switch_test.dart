import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_mode_switch.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_reading_runtime.dart';

void main() {
  const request = ReaderModeSwitchRequest(
    fromMode: 'scroll',
    toMode: 'page',
    chapterId: 'c1',
    anchorCharOffset: 420,
  );

  group('ReaderModeSwitchManager（B7：请求化 + Runtime 唯一权威）', () {
    test('begin 登记请求：isActive 与锚点投影生效', () {
      final manager = ReaderModeSwitchManager();
      expect(manager.isActive, isFalse);
      expect(manager.request, isNull);

      manager.begin(request);
      expect(manager.isActive, isTrue);
      expect(manager.request, same(request));
    });

    test('complete 终结切换：isActive 归假、锚点清空', () {
      final manager = ReaderModeSwitchManager();
      manager.begin(request);
      manager.complete();
      expect(manager.isActive, isFalse);
      expect(manager.request, isNull);
      // 幂等：重复 complete 无副作用。
      manager.complete();
      expect(manager.isActive, isFalse);
    });

    test('新 begin 取代旧请求（连续切换竞态的语义基础）', () {
      final manager = ReaderModeSwitchManager();
      manager.begin(request);
      const second = ReaderModeSwitchRequest(
        fromMode: 'page',
        toMode: 'scroll',
        chapterId: 'c1',
        anchorCharOffset: 88,
      );
      manager.begin(second);
      expect(manager.request, same(second));
      expect(manager.isActive, isTrue);
    });

    test('请求按值相等：同 fromMode/toMode/chapterId/anchor 视为同一请求', () {
      expect(
        const ReaderModeSwitchRequest(
          fromMode: 'scroll',
          toMode: 'page',
          chapterId: 'c1',
          anchorCharOffset: 420,
        ),
        equals(request),
      );
      expect(
        const ReaderModeSwitchRequest(
          fromMode: 'scroll',
          toMode: 'page',
          chapterId: 'c1',
          anchorCharOffset: 421,
        ),
        isNot(equals(request)),
      );
    });
  });

  group('ReaderReadingRuntime.changeMode（B7 编排）', () {
    test('changeMode 登记请求并失效在途续作（场景 C 同构）', () {
      final runtime = ReaderReadingRuntime();
      final token = runtime.operationToken.issue();

      runtime.changeMode(request);
      expect(runtime.isModeSwitchActive, isTrue);
      expect(runtime.modeSwitchAnchor, 420);
      // 在途续作（旧切换/恢复/程序化滚动的凭证）整体失效。
      expect(runtime.operationToken.isCurrent(token), isFalse);
    });

    test('completeModeSwitch 终结后守卫投影归零', () {
      final runtime = ReaderReadingRuntime();
      runtime.changeMode(request);
      runtime.completeModeSwitch();
      expect(runtime.isModeSwitchActive, isFalse);
      expect(runtime.modeSwitchAnchor, isNull);
    });

    test('二次 changeMode 取代旧请求；旧定位回调凭请求值比对丢弃', () {
      final runtime = ReaderReadingRuntime();
      runtime.changeMode(request);
      final staleRequest = runtime.modeSwitch.request;

      const refreshed = ReaderModeSwitchRequest(
        fromMode: 'scroll',
        toMode: 'page',
        chapterId: 'c1',
        anchorCharOffset: 1000,
      );
      runtime.changeMode(refreshed);

      // 模拟旧定位回调迟到完成：请求已被取代 → 不得终结新切换。
      expect(staleRequest == runtime.modeSwitch.request, isFalse);
      expect(runtime.modeSwitchAnchor, 1000);
    });
  });
}
