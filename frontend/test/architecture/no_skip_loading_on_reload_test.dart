import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 架构棘轮：lib/ 内禁止 `skipLoadingOnReload`。
///
/// 本项目 AsyncValue 的 isReloading 唯一来源是会话世代（sessionEpochProvider）
/// 变化，即换号。此时保留旧数据渲染（skipLoadingOnReload: true）会把上一
/// 账号内容显示给新账号——曾两次实机复发“换号闪旧数据”的渲染层元凶。
/// 同账号刷新不闪 loading 由 when 的 skipLoadingOnRefresh（默认 true）承担。
void main() {
  test('lib 内不存在 skipLoadingOnReload', () {
    final offenders = <String>[];
    final dir = Directory('lib');
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final parts = entity.path.split(Platform.pathSeparator);
      if (parts.contains('l10n')) {
        continue;
      }
      if (entity.readAsStringSync().contains('skipLoadingOnReload')) {
        offenders.add(entity.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          '以下文件使用 skipLoadingOnReload，换号时会渲染上一账号数据：\n'
          '${offenders.join('\n')}',
    );
  });
}
