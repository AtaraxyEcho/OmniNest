import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 动画时长接入「减少动态效果」的存量闸门。
///
/// 系统开启减少动效后，纯装饰的淡入、位移与状态渐变应当直接落终态。已接好的
/// 写法有两种：时长过 `MotionToken.reduced` / `resolveForPlatform`，或在
/// `initState` 里按 `prefersReducedOnPlatform()` 决定不启动控制器。
/// 这里只盯"动画位置上写了字面量时长"的行：`duration:` 参数同现 `Duration(`
/// 且该行没提 MotionToken。
///
/// 存量按实测登记，只许降不许升：修掉一处就把上限改小，并把文件从注释里的
/// 待接入清单挪走。本轮（2026-11-03）已接入的文件：
/// lib/core/widgets/workstation_controls.dart、lib/core/widgets/animated_card.dart、
/// lib/features/admin/presentation/widgets/admin_shell.dart（分区淡入走 reduced；
/// 1600ms 状态灯脉冲保留字面量时长，由 `prefersReducedOnPlatform()` 决定不启动控制器，
/// 因此仍会出现在本闸门的清单里，属已判定不是漏接）、
/// lib/features/files/presentation/pages/file_browser_page_navigation.dart、
/// lib/features/reader/presentation/widgets/reader_view_page_builders_return.dart、
/// lib/features/reader/presentation/pages/reader_view_page_commands.dart。
void main() {
  // 2026-11-04 实测：再接入 mobile_env_widgets/app_dropdown/file_browser_page_external 后，
  // 全仓剩余 83 处字面量动画时长。
  const hardcodedMotionCeiling = 83;

  test('未接入减动效判定的动画时长不得新增', () {
    final offenders = <String>[];
    final literalDuration = RegExp(r'duration:.*Duration\(');

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll('\\', '/');
      if (path == 'lib/core/theme/motion_token.dart') {
        continue;
      }
      final lines = entity.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (literalDuration.hasMatch(line) && !line.contains('MotionToken.')) {
          offenders.add('$path:${index + 1}');
        }
      }
    }

    expect(
      offenders.length,
      lessThanOrEqualTo(hardcodedMotionCeiling),
      reason:
          '未走 MotionToken 的动画时长从 $hardcodedMotionCeiling 涨到 '
          '${offenders.length} 处：${offenders.join(', ')}',
    );
  });
}
