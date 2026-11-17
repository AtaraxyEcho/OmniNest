import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 异步状态回写棘轮：禁止「await 前抓快照、await 后整份发布」。
///
/// `AsyncNotifier` 的手动方法里，若完成回调用 `await` **之前**抓的状态快照做发布基准，
/// 那段窗口里发生的写入会被旧快照无声覆盖。Files 模块的真实事故是移动端点分区卡后
/// 「子页态」被写回 false，页面闪一下就弹回模块首页（见 commit `a8cfb34c`）；同一形状
/// 会丢任何字段：多选、视图模式、播放队列、阅读进度、分页窗口、错误位。
///
/// 判据是「最后一次实况读取之后是否还出现过 await」：
/// - `final x = state.asData?.value`（含 `?? 兜底`）算一次实况读取，把 `x` 记为可用基准；
/// - 之后一旦出现 `await`，此前记录的基准全部作废；
/// - 此时若发布语句的 `copyWith` 接收者仍是某个作废基准，即判违规。
/// 走 `_liveOr(...)`/`_liveState` 助手、或发布新构造对象的，不在本条约束内。
///
/// 确属例外（例如发布的就是那一刻定格的旧值）必须按 `路径:行` 登记原因，禁止空手放行。
void main() {
  const scanRoots = <String>['lib/features', 'lib/app', 'lib/core'];
  final relevantPattern = RegExp(r'asData|_currentState');
  final memberStartPattern = RegExp(
    r'^(  |        )[A-Za-z_][A-Za-z0-9_<>?, .]* [a-zA-Z_][A-Za-z0-9_]*\(',
  );
  // 实况读取：允许带 `?? 兜底`，但不允许是别的表达式来源。
  final liveReadPattern = RegExp(
    r'^\s*final\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(state\.asData\?\.value|state\.value|_currentState)(\s|\?|;)',
  );
  final publishPattern = RegExp(
    r'^\s*(state\s*=\s*(AsyncData|AsyncValue\.data)|_emitState\()',
  );
  const compliantMarkerPattern = r'_liveOr\(|_liveState\b|AsyncValue\.error';
  const allowedViolations = <String, String>{};

  test('异步回写不得用 await 前的快照整份覆盖实况', () {
    final found = <String>{};

    for (final root in scanRoots) {
      final directory = Directory(root);
      if (!directory.existsSync()) {
        continue;
      }
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final path = entity.path.replaceAll('\\', '/');
        final lines = entity.readAsLinesSync();
        if (!relevantPattern.hasMatch(lines.join('\n'))) {
          continue;
        }

        var liveBases = <String>{};
        var awaitedAfterLastRead = false;
        for (var index = 0; index < lines.length; index++) {
          final line = lines[index];
          if (memberStartPattern.hasMatch(line)) {
            liveBases = <String>{};
            awaitedAfterLastRead = false;
          }

          final read = liveReadPattern.firstMatch(line);
          if (read != null) {
            // 新读到的实况作废之前的 await 计数：它比旧快照更靠近发布点。
            liveBases = <String>{read.group(1)!};
            awaitedAfterLastRead = false;
            continue;
          }
          if (liveBases.isEmpty) {
            continue;
          }
          if (line.contains('await ')) {
            awaitedAfterLastRead = true;
            continue;
          }
          if (!publishPattern.hasMatch(line)) {
            continue;
          }
          final end = index + 2 < lines.length ? index + 3 : lines.length;
          final statement = lines.sublist(index, end).join(' ');
          if (RegExp(compliantMarkerPattern).hasMatch(statement)) {
            liveBases = <String>{};
            awaitedAfterLastRead = false;
            continue;
          }
          final usesStaleBase = liveBases.any(
            (name) => RegExp('\\b$name\\.copyWith\\(').hasMatch(statement),
          );
          if (awaitedAfterLastRead && usesStaleBase) {
            found.add('$path:${index + 1}');
          }
          liveBases = <String>{};
          awaitedAfterLastRead = false;
        }
      }
    }

    final unexpected =
        found.difference(allowedViolations.keys.toSet()).toList()..sort();
    final stale =
        allowedViolations.keys.toSet().difference(found).toList()..sort();

    expect(
      unexpected,
      isEmpty,
      reason:
          '新增「await 前快照整份发布」的回写点，请改成发布时刻重读实况'
          '（_liveOr(快照) 或发布前重新取 state.asData?.value）：\n'
          '${unexpected.join('\n')}',
    );
    expect(stale, isEmpty, reason: '以下存量已收敛，请从清单删除：\n${stale.join('\n')}');
  });
}
