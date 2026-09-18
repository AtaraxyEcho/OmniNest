import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// lib/ 内禁止裸调用 debugPrint/debugPrintStack（release 会外泄内部诊断）；
/// 统一走 core/log/dev_log.dart 的 kDebugMode 门控。
void main() {
  test('lib 禁止未门控的 debugPrint 调用', () {
    final violations = <String>[];
    final pattern = RegExp(r'\bdebugPrint(Stack)?\s*\(');
    const allowlist = <String>{'lib/core/log/dev_log.dart'};

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll('\\', '/');
      if (allowlist.contains(path) ||
          path.startsWith('lib/app/l10n/app_localizations')) {
        continue;
      }
      final content = entity.readAsStringSync();
      for (final line in content.split('\n')) {
        if (pattern.hasMatch(line) && !line.trimLeft().startsWith('//')) {
          violations.add('$path: ${line.trim()}');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          '请改用 devLog/devLogStack（core/log/dev_log.dart）：\n${violations.join('\n')}',
    );
  });
}
