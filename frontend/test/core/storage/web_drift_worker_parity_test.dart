import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Web 端 drift 两个手工落盘的产物必须与解析到的包版本同代。
///
/// `web/sqlite3.wasm` 与 `web/drift_worker.js` 是复制进仓库的静态资源，`flutter build web`
/// 只搬运不校验：升级 drift 后只换其中一个，wasm 的导入符号与 worker 提供的那一套就对不上，
/// `WebAssembly.instantiate` 直接 LinkError，drift 库在浏览器里根本打不开。症状是阅读页
/// 「章节内容加载失败」而后端一切正常，没有任何日志指向这两个文件。
void main() {
  test('web/drift_worker.js 与 drift 包内的 worker 是同一份', () {
    final packageConfig = File('.dart_tool/package_config.json');
    if (!packageConfig.existsSync()) {
      markTestSkipped('未执行 pub get，跳过 Web drift 产物配对校验');
      return;
    }
    final configured = _packageRoot(packageConfig, 'drift');
    if (configured == null) {
      markTestSkipped('package_config.json 里没有 drift，跳过 Web drift 产物配对校验');
      return;
    }
    final canonical = File(p.join(configured.toFilePath(), 'drift_worker.js'));
    final vendored = File('web/drift_worker.js');
    if (!canonical.existsSync() || !vendored.existsSync()) {
      fail(
        'Web drift 产物缺失：worker=${vendored.existsSync()} 包内=${canonical.existsSync()}',
      );
    }

    expect(
      vendored.readAsBytesSync(),
      equals(canonical.readAsBytesSync()),
      reason:
          'web/drift_worker.js 与 ${canonical.path} 不一致：升级 drift 后要把包内那份'
          '整体复制进 web/，否则 sqlite3.wasm 的导入符号在 worker 里找不到，'
          '浏览器端 drift 库打不开，阅读页只会显示「章节内容加载失败」。',
    );
  });
}

Uri? _packageRoot(File packageConfig, String name) {
  final decoded =
      jsonDecode(packageConfig.readAsStringSync()) as Map<String, dynamic>;
  final packages = (decoded['packages'] as List).cast<Map<String, dynamic>>();
  for (final entry in packages) {
    if (entry['name'] != name) {
      continue;
    }
    final rootUri = Uri.parse(entry['rootUri'] as String);
    return packageConfig.parent.uri.resolve(rootUri.toString());
  }
  return null;
}
