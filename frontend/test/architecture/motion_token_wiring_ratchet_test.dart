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
  // 2026-11-06 实测剩余 40 处（歌词跟随滚动已改为按行间隔动态计算并钳制）：
  //   music 21 —— 其余为 Ticker 周期、Toast 停留等非过渡时长，接入前需逐站判定；
  //   photos 9 —— 幻灯转场与 chrome 7 处的时长本身待拍板，另有 2 处（详情页与灯箱翻页）
  //     受各自行数棘轮限制，接 token 需要先把页面按职责拆分；
  //   portal 4 —— 天气与环境类循环动画 3 处（归零会变成逐帧空转）+ 1 处 snackbar 停留时长；
  //   files 2 / reader 2 / video 1 / admin 1 —— snackbar 停留时长（非动画，按行匹配的误报），
  //     以及与动画时序耦合的阅读器翻页控制器、admin 状态灯脉冲。
  const hardcodedMotionCeiling = 40;

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
