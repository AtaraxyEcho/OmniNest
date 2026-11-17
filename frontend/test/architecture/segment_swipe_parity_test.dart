import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 分段切换只允许一种跟手实现（D4 裁定，2026-10-14）。
///
/// 托管分段面（媒体库/照片/音乐/影视）一律走 `MobileSegmentPager`。
/// `MobileSectionSwipe` 是甩动跳格的速度检测器，观感低于 Library 既有水准，
/// 裁定要求把弱的升上来、不是把 Library 降下去，因此它只允许留在
/// **没有邻位可分页**的那一个调用点：影视工位窄窗与不在四段次序内的管理分区
/// （那里仍需要"一划切回四段"，而分页会把窄窗顶栏画两份、把管理分区顶成首段）。
///
/// 白名单之外出现新的引用就说明有人又把甩动跳格挂到了分段面上。
void main() {
  const allowed = <String>{
    'lib/features/video/presentation/widgets/movie_shell_mobile.dart',
  };
  const definition = 'lib/core/widgets/mobile_section_swipe.dart';

  test('MobileSectionSwipe 不再新增调用点', () {
    final libDir = Directory('lib');
    expect(libDir.existsSync(), isTrue, reason: '应在 frontend/ 下运行');

    final offenders = <String>[];
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll(r'\', '/');
      if (path == definition) {
        continue;
      }
      if (!entity.readAsStringSync().contains('MobileSectionSwipe')) {
        continue;
      }
      if (!allowed.contains(path)) {
        offenders.add(path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '分段切换必须用 MobileSegmentPager；下列文件新引用了甩动跳格检测器：'
          '\n${offenders.join('\n')}',
    );
  });

  test('检测器定义与白名单仍然成立', () {
    // 白名单里的文件若已不再引用它，就该把这里一并收掉，别留悬空许可。
    for (final path in allowed) {
      final file = File(path);
      expect(
        file.existsSync() &&
            file.readAsStringSync().contains('MobileSectionSwipe'),
        isTrue,
        reason: '$path 已不再使用 MobileSectionSwipe，应从白名单移除并删除检测器',
      );
    }
  });
}
