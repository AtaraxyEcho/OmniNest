/// 外部下载地址的协议收口判定。
///
/// 独立成纯函数是为了让 Web 实现可被单元测试覆盖：条件导入的平台文件
/// 在 `flutter test` 里跑不到，协议白名单只能靠人眼审。
library;

/// 允许直接交给浏览器或系统打开的下载目标。
///
/// 下载链接来自外部元数据或后台配置，`javascript:`、`data:text/html` 之类
/// 一旦原样交给 `window.open` 就是在本页同源环境里执行脚本。
///
/// 无协议时只认「单斜杠开头的同源路径」：`//host/path` 是协议相对地址，
/// 浏览器会补上当前协议跳到另一个源；浏览器还把反斜杠当分隔符，
/// `/\host` 同样逃逸，两者都不能算同源相对路径。
bool isSafeDownloadTarget(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  if (_controlChars.hasMatch(trimmed)) {
    return false;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null) {
    return false;
  }
  if (!uri.hasScheme) {
    return trimmed.startsWith('/') &&
        !trimmed.startsWith('//') &&
        !trimmed.contains(r'\');
  }
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}

final RegExp _controlChars = RegExp(r'[\x00-\x1f\x7f]');
