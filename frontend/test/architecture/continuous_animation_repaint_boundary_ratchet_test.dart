import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 架构棘轮：包含 `.repeat(` 常驻连续动画的展示层文件必须显式隔离重绘。
///
/// 60fps 循环动画（天气粒子、频谱条、呼吸圆点、扫码激光）如果不包
/// `RepaintBoundary`，每帧会把父级卡片或整行列表一起标脏，滚动时在
/// GPU/UI 线程上放大成整屏合成。新增此类动画时先隔离绘制节点。
void main() {
  /// 逐站复核后确认已由其它机制隔离重绘的例外（默认为空，不得随意放行）。
  const exemptFiles = <String>{};

  test('包含 .repeat( 的展示层文件必须使用 RepaintBoundary 隔离重绘', () {
    final offenders = <String>[];
    for (final entity in Directory('lib/features').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll('\\', '/');
      if (!path.contains('/presentation/') || exemptFiles.contains(path)) {
        continue;
      }
      final source = entity.readAsStringSync();
      if (source.contains('.repeat(') && !source.contains('RepaintBoundary')) {
        offenders.add(path);
      }
    }
    offenders.sort();

    expect(
      offenders,
      isEmpty,
      reason:
          '以下展示层文件启动了 .repeat( 循环动画但未包裹 RepaintBoundary：\n'
          '${offenders.join('\n')}',
    );
  });
}
