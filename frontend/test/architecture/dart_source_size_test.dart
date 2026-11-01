import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'source_size_baseline.dart';

const _maximumSourceLines = 1200;
const _softMaximumSourceLines = 800;

/// 0.1.0 发布前登记的存量超长源码；禁止新增，拆分完成后从清单移除。
const _allowedOversizedSources = <String>{
  'test/features/music/music_controller_test.dart',
};

/// 已登记的生产源码 800-1200 行存量；禁止新增，拆分完成后从清单移除。
/// 测试代码只受 1200 行硬线约束，不计入软上限登记。
final _allowedSoftOversizedSources = sourceLineCaps.keys.toSet();

void main() {
  test('手写 Dart 源码不超过 1200 行', () async {
    final oversizedSources = await _collectOversizedSources(
      roots: const <String>['lib', 'test'],
      maxLines: _maximumSourceLines,
      allowedSources: _allowedOversizedSources,
    );

    expect(
      oversizedSources,
      isEmpty,
      reason: '手写 Dart 源码超过 1200 行，请按职责拆分：\n${oversizedSources.join('\n')}',
    );
  });

  test('生产 Dart 源码超过 800 行必须登记', () async {
    final oversizedSources = await _collectOversizedSources(
      roots: const <String>['lib'],
      maxLines: _softMaximumSourceLines,
      allowedSources: _allowedSoftOversizedSources,
    );

    expect(
      oversizedSources,
      isEmpty,
      reason:
          '生产 Dart 源码超过 800 行且未登记，请先规划拆分并登记存量：\n'
          '${oversizedSources.join('\n')}',
    );
  });
}

Future<List<String>> _collectOversizedSources({
  required List<String> roots,
  required int maxLines,
  required Set<String> allowedSources,
}) async {
  final oversizedSources = <String>[];
  for (final sourceRoot in roots) {
    await for (final entity in Directory(sourceRoot).list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final normalizedPath = entity.path.replaceAll('\\', '/');
      if (isGeneratedDartSource(normalizedPath)) {
        continue;
      }
      final lineCount = (await entity.readAsLines()).length;
      if (lineCount > maxLines && !allowedSources.contains(normalizedPath)) {
        oversizedSources.add('$normalizedPath lines=$lineCount');
      }
    }
  }
  oversizedSources.sort();
  return oversizedSources;
}
