import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 配额文案的守卫闸门。
///
/// `quotaBytes < 0` 是"不限额"的哨兵值，不是容量。存储统计页一开始就按
/// `isQuotaUnlimited` 分支走专用文案，移动端首页的存储卡漏了这个分支，
/// 于是把哨兵值直接格式化成了「共 -1 B」摆在工作区首页上。
///
/// 这类缺陷的复发形态就是"又多一个调用点、又忘带守卫"，所以按文件成对检查，
/// 而不是只测某一个页面。
void main() {
  const quotaLineCall = 'filesStorageQuotaLine(';
  const unlimitedGuard = 'isQuotaUnlimited';

  test('每个渲染配额行的文件都必须带不限额守卫', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: '本测试必须在 frontend 根目录下运行');

    final callSites = <String>[];
    final unguarded = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final relative = entity.path.replaceAll('\\', '/');
      if (relative.contains('/l10n/')) {
        continue;
      }
      final source = entity.readAsStringSync();
      if (!source.contains(quotaLineCall)) {
        continue;
      }
      callSites.add(relative);
      if (!source.contains(unlimitedGuard)) {
        unguarded.add(relative);
      }
    }

    expect(
      callSites,
      hasLength(2),
      reason:
          '配额行调用点数量变了（当前 ${callSites.join(", ")}）。'
          '新增调用点请同步本测试的期望数量，并确认它带不限额守卫',
    );
    expect(
      unguarded,
      isEmpty,
      reason: '这些文件渲染了配额行但没有 $unlimitedGuard 分支：${unguarded.join(", ")}',
    );
  });
}
