import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 字号治理棘轮：lib/features 禁止新增裸数字字号。
///
/// 基线 `tool/font_size_baseline.txt` 记录存量（每文件允许的违规数），
/// 迁移批次完成后销号递减；基线清零后本测试即全量阻断。
/// 白名单行级标记：`// ignore: font_size_whitelist`。
void main() {
  test('lib/features 禁止新增裸数字字号（基线棘轮）', () {
    final featuresDir = Directory('lib/features');
    expect(featuresDir.existsSync(), isTrue, reason: '本测试必须在 frontend 根目录下运行');

    const whitelistMarker = '// ignore: font_size_whitelist';
    final fontSizePattern = RegExp(r'fontSize:\s*[0-9]');
    final videoHelperPattern = RegExp(
      r'(?:serif|display|body|mono)\(\s*(?:size:\s*)?[0-9]',
    );

    final violations = <String, int>{};
    final details = <String>[];
    for (final entity in featuresDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final relative = entity.path.replaceAll('\\', '/');
      final isVideoModule = relative.startsWith('lib/features/video/');
      final lines = entity.readAsLinesSync();
      var count = 0;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.contains(whitelistMarker)) {
          continue;
        }
        final isViolation =
            fontSizePattern.hasMatch(line) ||
            (isVideoModule && videoHelperPattern.hasMatch(line));
        if (isViolation) {
          count += 1;
          details.add('$relative:${i + 1}');
        }
      }
      if (count > 0) {
        violations[relative] = count;
      }
    }

    final baselineFile = File('tool/font_size_baseline.txt');
    expect(
      baselineFile.existsSync(),
      isTrue,
      reason: '缺少字号基线文件 tool/font_size_baseline.txt',
    );
    final baseline = <String, int>{};
    for (final line in baselineFile.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }
      final parts = trimmed.split(RegExp(r'\s+'));
      expect(parts, hasLength(2), reason: '基线格式应为「路径 数量」：$trimmed');
      baseline[parts[0]] = int.parse(parts[1]);
    }

    final regressions = <String>[];
    var actualTotal = 0;
    var baselineTotal = 0;
    for (final entry in violations.entries) {
      actualTotal += entry.value;
      final allowed = baseline[entry.key];
      if (allowed == null) {
        regressions.add('新增违规文件 ${entry.key}（${entry.value} 处）');
      } else if (entry.value > allowed) {
        regressions.add(
          '${entry.key} 超出基线 ${entry.value - allowed} 处'
          '（当前 ${entry.value} / 允许 $allowed）',
        );
      }
    }
    for (final entry in baseline.entries) {
      baselineTotal += entry.value;
      final actual = violations[entry.key] ?? 0;
      if (actual < entry.value) {
        regressions.add(
          '基线待销号：${entry.key}（当前 $actual / 基线 ${entry.value}），'
          '请从 tool/font_size_baseline.txt 删除或下调该条目',
        );
      }
    }

    // ignore: avoid_print
    print('字号违规 actual=$actualTotal baseline=$baselineTotal');
    if (regressions.isNotEmpty) {
      // ignore: avoid_print
      print('违规明细（前 60 条）：\n${details.take(60).join('\n')}');
    }
    expect(
      regressions,
      isEmpty,
      reason:
          '字号棘轮回归：请迁移至 AppTypography 语义 token，'
          '或按治理规程销号/更新基线',
    );
  });
}
