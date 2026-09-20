import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/utils/clipboard_fallback_stub.dart';
import 'package:omninest/core/utils/clipboard_writer.dart';

/// 剪贴板写入包装：平台 Clipboard 可用时直写；Web 非安全上下文抛
/// PlatformException(copy_fail) 时回退 DOM execCommand（VM 测试环境
/// 走 stub，恒返回 false）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('平台剪贴板可用时写入成功', () async {
    final ok = await copyTextToClipboard('hello');

    expect(ok, isTrue);
  });

  test('非 Web 平台回退桩恒返回 false', () {
    expect(clipboardFallbackCopy('hello'), isFalse);
  });
}
