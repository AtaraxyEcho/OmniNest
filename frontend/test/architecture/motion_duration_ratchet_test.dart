import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 动画时长必须走 `MotionToken`；确需超长时长的按文件+毫秒数登记存量，禁止新增。
///
/// 本项目对交互动效的预算是 <320ms（`MotionToken.normal` 300ms 是上限档），
/// 超出的一律要么改用 token，要么在这里写明保留原因。判定只看"时长出现在
/// 动画位置上"：`duration:` 具名参数，或名字含 Transition/Animation/Fade/Slide 的常量。
void main() {
  const maxMotionMillis = 320;
  const allowedViolations = <String, String>{
    // 幻灯转场时长属已挂起的设计决策（450ms 转场方向），等定稿再收。
    'lib/features/photos/presentation/pages/photo_slideshow_page.dart 450':
        '幻灯翻页转场时长待拍板',
    'lib/features/photos/presentation/widgets/photo_slideshow_chrome.dart 400':
        '幻灯 chrome 淡入淡出，随转场决策一并处理',
    'lib/features/photos/presentation/widgets/photo_slideshow_overlays.dart 400':
        '幻灯遮罩与队列层淡入，随转场决策一并处理',
    // 音乐区由并行会话持有，本轮不越界改其时长。
    'lib/features/music/presentation/deck/music_deck_shell.dart 360':
        '并行会话在途文件',
    'lib/features/music/presentation/player/music_immersive_cover_deck_widgets.dart 1400':
        '沉浸卡组轮播节奏，非交互反馈',
    'lib/features/music/presentation/player/music_immersive_lyric_line.dart 1400':
        '歌词行推进节奏，非交互反馈',
    'lib/features/music/presentation/widgets/music_platform_qr_panel.dart 2800':
        '二维码刷新倒计时环，属内容节奏',
    // 数据/进度动画：与 MotionToken.chart 同档，不是交互反馈。
    'lib/features/admin/presentation/widgets/admin_shell.dart 1600': '工作区指示动画',
    'lib/features/portal/presentation/widgets/portal_mobile_system_widgets.dart 600':
        '进度条填充动画',
    'lib/features/portal/presentation/widgets/storage_overview_widget.dart 800':
        '存储环数据动画',
  };

  test('动画时长不得新增硬编码超预算值', () {
    final found = <String>{};

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll('\\', '/');
      if (path == 'lib/core/theme/motion_token.dart') {
        continue;
      }
      final isMotionPosition = RegExp(
        r'\bduration:.*?Duration\(\s*milliseconds:\s*(\d+)\s*\)'
        r'|(?:const\s+)?_\w*[Tt]ransition\w*[Dd]uration\s*=\s*(?:const\s+)?Duration\(\s*milliseconds:\s*(\d+)\s*\)'
        r'|(?:const\s+)?_\w*(?:[Aa]nimation|[Ff]ade|[Ss]lide)\w*[Dd]uration\s*=\s*(?:const\s+)?Duration\(\s*milliseconds:\s*(\d+)\s*\)',
      );
      for (final line in entity.readAsLinesSync()) {
        for (final match in isMotionPosition.allMatches(line)) {
          final millis = int.parse(
            match.group(1) ?? match.group(2) ?? match.group(3) ?? '0',
          );
          if (millis > maxMotionMillis) {
            found.add('$path $millis');
          }
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
      reason: '新增超预算动画时长，请改用 MotionToken：\n${unexpected.join('\n')}',
    );
    expect(stale, isEmpty, reason: '以下存量已收敛，请从清单删除：\n${stale.join('\n')}');
  });
}
