import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Windows `ui::AXTree` 静态语义守卫测试。
///
/// 在 Windows 平台上，Flutter 辅助功能桥会将 `opacity == 0` 且未开启
/// `alwaysIncludeSemantics: true` 的子树从语义树中临时摘除，待恢复时再挂回；
/// 若与 `AnimatedSwitcher` 退场子树或弹层动画并发触发，会导致
/// `ui::AXTree` 断链崩溃（"will not be in the tree and is not the new root"）。
///
/// 本守卫扫描 `frontend/lib/` 下所有源码，要求：
/// 1. 所有 `AnimatedOpacity(` 与 `FadeTransition(` 均显式设置
///    `alwaysIncludeSemantics: true`，或处于 `ExcludeSemantics(` 子树内；
/// 2. 所有 `AnimatedSwitcher(` 均使用 `excludeExitingSemanticsStack`，
///    或处于 `ExcludeSemantics(` 子树内。
void main() {
  test(
    'AnimatedOpacity 与 FadeTransition 必须具备 alwaysIncludeSemantics: true 或位于 ExcludeSemantics 内',
    () {
      final offenders = _scanOpacityAndFadeOffenders();
      expect(
        offenders,
        isEmpty,
        reason:
            '发现未开启 alwaysIncludeSemantics: true（且未包 ExcludeSemantics）的 '
            'AnimatedOpacity / FadeTransition，请补齐以防 Windows ui::AXTree 断链：\n'
            '${offenders.join('\n')}',
      );
    },
  );

  test(
    'AnimatedSwitcher 必须使用 excludeExitingSemanticsStack 或位于 ExcludeSemantics 内',
    () {
      final offenders = _scanAnimatedSwitcherOffenders();
      expect(
        offenders,
        isEmpty,
        reason:
            '发现未使用 excludeExitingSemanticsStack（且未包 ExcludeSemantics）的 '
            'AnimatedSwitcher，请补齐 layoutBuilder 以防 Windows ui::AXTree 断链：\n'
            '${offenders.join('\n')}',
      );
    },
  );
}

List<String> _scanOpacityAndFadeOffenders() {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    return const <String>['lib 目录不存在，请在 frontend/ 下运行'];
  }
  final offenders = <String>[];
  final widgetPattern = RegExp(
    r'(?<![A-Za-z0-9_])(AnimatedOpacity|FadeTransition)\s*\(',
  );
  final alwaysIncludePattern = RegExp(r'alwaysIncludeSemantics\s*:\s*true\b');

  for (final file in _listDartFiles(libDir)) {
    final path = file.path.replaceAll(r'\', '/');
    final raw = file.readAsStringSync();
    final masked = _maskCommentsAndStrings(raw);
    final excludeSpans = _findCallSpans(masked, 'ExcludeSemantics');

    for (final match in widgetPattern.allMatches(masked)) {
      final widgetName = match.group(1)!;
      final openParen = match.end - 1;
      final closeParen = _findMatchingParen(masked, openParen);
      if (closeParen == -1) continue;

      if (_isInsideAnySpan(match.start, excludeSpans)) {
        continue;
      }

      final argsSlice = masked.substring(openParen, closeParen + 1);
      if (!alwaysIncludePattern.hasMatch(argsSlice)) {
        final line = _lineNumberAt(raw, match.start);
        offenders.add('$path:$line ($widgetName)');
      }
    }
  }
  return offenders;
}

List<String> _scanAnimatedSwitcherOffenders() {
  final libDir = Directory('lib');
  if (!libDir.existsSync()) {
    return const <String>['lib 目录不存在，请在 frontend/ 下运行'];
  }
  final offenders = <String>[];
  final switcherPattern = RegExp(r'(?<![A-Za-z0-9_])AnimatedSwitcher\s*\(');

  for (final file in _listDartFiles(libDir)) {
    final path = file.path.replaceAll(r'\', '/');
    final raw = file.readAsStringSync();
    final masked = _maskCommentsAndStrings(raw);
    final excludeSpans = _findCallSpans(masked, 'ExcludeSemantics');

    for (final match in switcherPattern.allMatches(masked)) {
      final openParen = match.end - 1;
      final closeParen = _findMatchingParen(masked, openParen);
      if (closeParen == -1) continue;

      if (_isInsideAnySpan(match.start, excludeSpans)) {
        continue;
      }

      final argsSlice = masked.substring(openParen, closeParen + 1);
      if (!argsSlice.contains('excludeExitingSemanticsStack')) {
        final line = _lineNumberAt(raw, match.start);
        offenders.add('$path:$line (AnimatedSwitcher)');
      }
    }
  }
  return offenders;
}

List<File> _listDartFiles(Directory root) {
  final files = <File>[];
  for (final entity in root.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      files.add(entity);
    }
  }
  files.sort((a, b) => a.path.compareTo(b.path));
  return files;
}

/// 将注释与字符串字面量替换为等长空格（保留换行符），避免误报并保持偏移量一致。
String _maskCommentsAndStrings(String source) {
  final out = List<int>.from(source.codeUnits);
  final len = out.length;
  var i = 0;
  while (i < len) {
    final c = out[i];
    final next = i + 1 < len ? out[i + 1] : 0;

    // 行注释 //
    if (c == 0x2F && next == 0x2F) {
      out[i] = 0x20;
      out[i + 1] = 0x20;
      i += 2;
      while (i < len && out[i] != 0x0A) {
        out[i] = 0x20;
        i++;
      }
      continue;
    }

    // 块注释 /* ... */
    if (c == 0x2F && next == 0x2A) {
      out[i] = 0x20;
      out[i + 1] = 0x20;
      i += 2;
      while (i < len) {
        if (out[i] == 0x2A && i + 1 < len && out[i + 1] == 0x2F) {
          out[i] = 0x20;
          out[i + 1] = 0x20;
          i += 2;
          break;
        }
        if (out[i] != 0x0A) {
          out[i] = 0x20;
        }
        i++;
      }
      continue;
    }

    // 单引号 / 双引号字符串（含三引号）
    if (c == 0x27 || c == 0x22) {
      final quote = c;
      final isTriple =
          i + 2 < len && out[i + 1] == quote && out[i + 2] == quote;
      if (isTriple) {
        out[i] = 0x20;
        out[i + 1] = 0x20;
        out[i + 2] = 0x20;
        i += 3;
        while (i < len) {
          if (out[i] == 0x5C && i + 1 < len) {
            if (out[i] != 0x0A) out[i] = 0x20;
            if (out[i + 1] != 0x0A) out[i + 1] = 0x20;
            i += 2;
            continue;
          }
          if (out[i] == quote &&
              i + 2 < len &&
              out[i + 1] == quote &&
              out[i + 2] == quote) {
            out[i] = 0x20;
            out[i + 1] = 0x20;
            out[i + 2] = 0x20;
            i += 3;
            break;
          }
          if (out[i] != 0x0A) out[i] = 0x20;
          i++;
        }
      } else {
        out[i] = 0x20;
        i++;
        while (i < len && out[i] != 0x0A) {
          if (out[i] == 0x5C && i + 1 < len) {
            out[i] = 0x20;
            if (out[i + 1] != 0x0A) out[i + 1] = 0x20;
            i += 2;
            continue;
          }
          final ch = out[i];
          out[i] = 0x20;
          i++;
          if (ch == quote) break;
        }
      }
      continue;
    }

    i++;
  }
  return String.fromCharCodes(out);
}

List<(int, int)> _findCallSpans(String masked, String symbol) {
  final pattern = RegExp('(?<![A-Za-z0-9_])$symbol\\s*\\(');
  final spans = <(int, int)>[];
  for (final match in pattern.allMatches(masked)) {
    final openParen = match.end - 1;
    final closeParen = _findMatchingParen(masked, openParen);
    if (closeParen != -1) {
      spans.add((openParen, closeParen));
    }
  }
  return spans;
}

bool _isInsideAnySpan(int offset, List<(int, int)> spans) {
  for (final span in spans) {
    if (offset > span.$1 && offset < span.$2) {
      return true;
    }
  }
  return false;
}

int _findMatchingParen(String masked, int openIndex) {
  var depth = 0;
  for (var i = openIndex; i < masked.length; i++) {
    final ch = masked.codeUnitAt(i);
    if (ch == 0x28) {
      depth++;
    } else if (ch == 0x29) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

int _lineNumberAt(String source, int offset) {
  var line = 1;
  for (var i = 0; i < offset && i < source.length; i++) {
    if (source.codeUnitAt(i) == 0x0A) {
      line++;
    }
  }
  return line;
}
