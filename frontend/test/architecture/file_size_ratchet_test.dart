import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'source_size_baseline.dart';

/// 源码行数棘轮：存量长文件只能缩小，不能继续变大。
///
/// 阈值约束见 `dart_source_size_test.dart`；本用例锁定每个已登记文件的当前
/// 行数，防止长期在 800-1200 区间内缓慢膨胀，逼近硬线时才被迫拆。
void main() {
  test('已登记长文件不得超过棘轮基线', () {
    final violations = <String>[];
    for (final entry in sourceLineCaps.entries) {
      final file = File(entry.key);
      if (!file.existsSync()) {
        violations.add('${entry.key} 已不存在，请从基线删除');
        continue;
      }
      final lines = file.readAsLinesSync().length;
      if (lines > entry.value) {
        violations.add('${entry.key} lines=$lines cap=${entry.value}');
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          '已登记长文件继续变大，请先按职责拆分再提交；拆分后同步收紧基线：\n'
          '${violations.join('\n')}',
    );
  });

  test('超过 800 行的生产源码必须在基线登记', () {
    final unregistered = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll('\\', '/');
      if (isGeneratedDartSource(path)) {
        continue;
      }
      final lines = entity.readAsLinesSync().length;
      if (lines > 800 && !sourceLineCaps.containsKey(path)) {
        unregistered.add('$path lines=$lines');
      }
    }
    unregistered.sort();

    expect(
      unregistered,
      isEmpty,
      reason:
          '生产源码超过 800 行未登记。优先拆分；确需保留时在 '
          'source_size_baseline.dart 登记并锁定当前行数：\n'
          '${unregistered.join('\n')}',
    );
  });
}
