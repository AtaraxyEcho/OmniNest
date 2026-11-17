import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 禁止在 Riverpod 异步 build / FutureProvider 的 await 间隙之后调用 ref.watch。
///
/// Riverpod 要求所有依赖订阅（`ref.watch`）在第一个 `await` 之前同步完成；
/// 在异步间隙之后调用 `ref.watch` 会在 Provider 重建或依赖变更时引发竞态或冷启动漏读。
void main() {
  test('异步 Provider 构建体内不得在 await 之后调用 ref.watch', () {
    final violations = <String>[];
    final buildOrProviderStart = RegExp(
      r'Future<.+?>\s+build\s*\(|FutureProvider(?:\.\w+)?<.+?>\s*\(\s*\(\s*ref\s*',
    );

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll(r'\', '/');
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!buildOrProviderStart.hasMatch(lines[i])) {
          continue;
        }
        var depth = 0;
        var opened = false;
        var seenAwait = false;
        for (var cursor = i; cursor < lines.length; cursor++) {
          final line = lines[cursor];
          final trimmed = line.trim();
          if (!trimmed.startsWith('//')) {
            if (seenAwait && RegExp(r'\bref\.watch\s*\(').hasMatch(line)) {
              violations.add('$path:${cursor + 1}');
            }
            if (RegExp(r'\bawait\b').hasMatch(line)) {
              seenAwait = true;
            }
          }
          for (var c = 0; c < line.length; c++) {
            if (line[c] == '{') {
              depth++;
              opened = true;
            } else if (line[c] == '}') {
              depth--;
            }
          }
          if (opened && depth <= 0) {
            break;
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          '发现 await 之后调用 ref.watch（请在首个 await 前同步声明所有 ref.watch）：\n'
          '${violations.join('\n')}',
    );
  });
}
