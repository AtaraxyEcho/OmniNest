import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files 工位面的三枚语义色只有一个入口：`context.filesColors.success/warning/error`。
///
/// `FilesWorkstationPalette.emerald/amber/rose` 是 `darkColors` 那一档的取值；
/// 直接引用它就等于把暗档前景抄进浅档，实测只有 1.82-3.19:1。同名 Deep 值是
/// `lightColors` 的对应档，由 `filesColors` 按亮度切换，调用点不需要知道亮度。
void main() {
  const allowed = <String>{
    // 检视面板拿这三枚做文件类型编码（图片/文档/文件夹），不是状态语义。
    // 要不要把它并到 FileEnvTypeColors 那张带 OnPaper 同位的表，是跨皮肤的决定。
    'lib/features/files/presentation/widgets/file_inspector_panel.dart',
  };

  test('Files presentation 不直接取暗档语义亮彩', () {
    final pattern = RegExp(r'FilesWorkstationPalette\.(?:emerald|amber|rose)\b');
    final offenders = <String>[];
    for (final entity in Directory('lib/features/files').listSync(
      recursive: true,
    )) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll('\\', '/');
      // 调色板本体负责定义这两档，不在扫描范围。
      if (path.endsWith('files_workstation_theme.dart') ||
          allowed.contains(path)) {
        continue;
      }
      final hits = pattern.allMatches(entity.readAsStringSync()).length;
      if (hits > 0) {
        offenders.add('$path ($hits 处)');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          '状态语义色请走 context.filesColors.success/warning/error；'
          '类型编码若要复用亮彩请进 allowed 并写明理由：${offenders.join(', ')}',
    );
  });
}
