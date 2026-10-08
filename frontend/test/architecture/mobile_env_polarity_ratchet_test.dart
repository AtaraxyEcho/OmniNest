// 极性迁移棘轮：已接入极性表的文件不得再引用单极性的 MobileEnvColors，
// 未接入的引用总数只允许下降。防止新页面继续写死暗值。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _migrated = <String>[
  'lib/core/widgets/mobile_ui.dart',
  'lib/app/mobile_shell/workspace_tools_page.dart',
  'lib/features/notifications/presentation/pages/notification_page_mobile.dart',
  'lib/features/profile/presentation/pages/profile_mobile_view.dart',
  'lib/features/profile/presentation/widgets/change_password_dialog.dart',
  'lib/features/portal/presentation/widgets/portal_mobile_hosted_content.dart',
  'lib/features/library/presentation/widgets/library_space_widgets.dart',
  'lib/features/library/presentation/pages/library_space_page.dart',
];

/// 本轮起点实测值（405 处出现，按 allMatches 计；早先引用的 416/453 是 grep -c 的行数，会少算一行多次）；每接完一个面就把它降到新的计数。
const _remainingCeiling = 405;

void main() {
  test('已迁移文件不再引用 MobileEnvColors', () {
    for (final path in _migrated) {
      final source = File(path).readAsStringSync();
      expect(
        source.contains('MobileEnvColors.'),
        isFalse,
        reason: '$path 必须整体走 context.env，否则浅态会残留暗字面量',
      );
    }
  });

  test('未迁移的暗字面量引用不再增长', () {
    var total = 0;
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      if (entity.path.endsWith('mobile_env_colors.dart')) {
        continue;
      }
      total += 'MobileEnvColors.'.allMatches(entity.readAsStringSync()).length;
    }
    expect(
      total,
      lessThanOrEqualTo(_remainingCeiling),
      reason: '当前 $total 处；接完一个面请把 _remainingCeiling 降到新值',
    );
  });
}
