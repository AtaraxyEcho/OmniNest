import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/core/utils/download_url_policy.dart';

void main() {
  test('放行 http/https 与同源相对路径', () {
    expect(isSafeDownloadTarget('https://cdn.example.com/a.zip'), isTrue);
    expect(isSafeDownloadTarget('http://10.0.0.5/files/a.txt'), isTrue);
    expect(isSafeDownloadTarget('/api/v1/files/a/download'), isTrue);
    expect(isSafeDownloadTarget('  https://example.com/a  '), isTrue);
  });

  test('拒绝可执行协议与相对协议绕过', () {
    // window.open 收到这些串会在当前同源页面里执行脚本或渲染内联文档。
    expect(isSafeDownloadTarget('javascript:alert(1)'), isFalse);
    expect(isSafeDownloadTarget('JaVaScRiPt:alert(1)'), isFalse);
    expect(
      isSafeDownloadTarget('data:text/html,<script>alert(1)</script>'),
      isFalse,
    );
    expect(isSafeDownloadTarget('blob:https://example.com/uuid'), isFalse);
    expect(isSafeDownloadTarget('file:///C:/Windows/win.ini'), isFalse);
    expect(isSafeDownloadTarget('javascript\u0000:alert(1)'), isFalse);
    // 协议相对与反斜杠形式都会换源：不能当成同源相对路径放行。
    expect(isSafeDownloadTarget('//evil.example.com/a.zip'), isFalse);
    expect(isSafeDownloadTarget(r'/\evil.example.com/a.zip'), isFalse);
    expect(isSafeDownloadTarget('/api/v1//files/a'), isTrue);
    expect(isSafeDownloadTarget('relative/path/a.zip'), isFalse);
    expect(isSafeDownloadTarget(''), isFalse);
    expect(isSafeDownloadTarget('   '), isFalse);
  });
}
