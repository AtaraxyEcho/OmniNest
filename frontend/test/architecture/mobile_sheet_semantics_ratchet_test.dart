import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 自绘底部面板必须有模态语义（aria-modal 一支，2026-10-14）。
///
/// Material 的 `showModalBottomSheet` 不给面板内容挂任何 role（`bottom_sheet.dart`
/// 里只有 `Semantics` 的传播与命中行为设置），读屏因此听不到“这是一个对话框”。
/// 走 `WorkstationDialogFrame` 的面板已由该框架补上 role；其余各模块自己画内容的
/// 面板必须在 builder 根节点包 `MobileSheetSemantics`。
///
/// 待迁基线已随最后一批 music 面板收口清零，本闸门自此是硬规则而不是棘轮。
void main() {
  /// 工位面板共用入口不在此列：它的内容通常就是 `WorkstationDialogFrame`，
  /// role 已由框架挂在面板子树上，再包一层会变成嵌套对话框。
  const exempt = <String>{'lib/core/widgets/workstation_mobile_sheet.dart'};

  List<String> scan() {
    final callPattern = RegExp(r'showModalBottomSheet[<(]');
    final offenders = <String>[];
    final libDir = Directory('lib');
    if (!libDir.existsSync()) {
      return const ['lib 目录不存在，请在 frontend/ 下运行'];
    }
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll(r'\', '/');
      if (exempt.contains(path)) {
        continue;
      }
      final text = entity.readAsStringSync();
      final rawCalls =
          text
              .split('\n')
              .where((line) => !line.trim().startsWith('//'))
              .where((line) => callPattern.hasMatch(line))
              .length;
      if (rawCalls == 0) {
        continue;
      }
      if (!text.contains('MobileSheetSemantics')) {
        offenders.add('$path ($rawCalls 处)');
      }
    }
    return offenders;
  }

  test('裸 showModalBottomSheet 必须已包 MobileSheetSemantics', () {
    final offenders = scan();
    expect(
      offenders,
      isEmpty,
      reason: '出现未包模态语义的底部面板，请在 builder 根节点补包装：$offenders',
    );
  });
}
