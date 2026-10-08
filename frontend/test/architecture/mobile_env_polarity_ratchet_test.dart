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
  'lib/features/portal/presentation/widgets/weather_detail_sheet.dart',
  'lib/features/files/presentation/pages/file_browser_page.dart',
  'lib/features/files/presentation/pages/file_browser_page_batch.dart',
  'lib/features/files/presentation/pages/file_browser_page_mobile_actions.dart',
  'lib/features/files/presentation/pages/file_browser_page_mobile_home.dart',
  'lib/features/files/presentation/pages/file_browser_page_storage_stats.dart',
  'lib/features/files/presentation/pages/file_mobile_folder_view.dart',
  'lib/features/files/presentation/pages/file_mobile_section_views.dart',
  'lib/features/files/presentation/widgets/file_env_glyph.dart',
  'lib/app/theme/mobile_env_theme.dart',
  'lib/features/files/presentation/widgets/share_link_sheet.dart',
  'lib/features/files/presentation/widgets/share_link_sheet_mobile.dart',
  'lib/app/mobile_shell/mobile_account_sheet.dart',
  'lib/features/backdrop/presentation/mobile_env_settings_sheet.dart',
  'lib/features/search/presentation/pages/mobile_search_page.dart',
  'lib/core/widgets/mobile_sample_kit.dart',
  'lib/core/widgets/mobile_status_kit.dart',
  'lib/features/photos/presentation/widgets/photo_editor_configs.dart',
  'lib/features/photos/presentation/widgets/photo_hosted_chrome.dart',
  'lib/features/music/presentation/player/music_mobile_now_playing.dart',
  'lib/features/music/presentation/player/music_mobile_now_playing_pages.dart',
  'lib/features/video/presentation/widgets/redesign/movie_redesign_mobile_chips.dart',
];

/// 本轮起点实测值（117 处出现，按 allMatches 计；早先引用的 416/453 是 grep -c 的行数，会少算一行多次）；每接完一个面就把它降到新的计数。
const _remainingCeiling = 117;

/// 经 PopupRoute/Dialog 推入的面板拿不到空间子树的 Theme 注册，
/// 必须自带 MobileEnvironmentScope，否则浅态下整张面板仍是暗值。
const _mustCarryScope = <String>[
  'lib/features/portal/presentation/widgets/weather_detail_sheet.dart',
];

/// 已迁移文件里残留的裸白前景/描边。
///
/// 这些文件已经按 context.env 解析颜色，再出现硬编码白值就意味着浅态不会翻。
/// 计数里含少量刻意保留项（例如影院 hero 次钮压在海报图上，白描边与深玻璃
/// 由图片本身提供对比），所以这里是天花板而不是零：下调它要么真的修掉一处，
/// 要么在代码里写明为什么保留。
const _bareLightLiteralCeiling = 22;

void _assertBareLightLiterals() {
  final pattern = RegExp(r'Colors\.white\b|Color\(0x[0-9A-Fa-f]{2}FFFFFF\)');
  var total = 0;
  final offenders = <String>[];
  for (final path in _migrated) {
    final source = File(path).readAsStringSync();
    final lines = source.split('\n');
    var hits = 0;
    var offset = 0;
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final next = offset + line.length + 1;
      final before = index > 0 ? lines[index - 1] : '';
      if (!before.contains('polarity-stable')) {
        hits += pattern.allMatches(line).length;
      }
      offset = next;
    }
    if (hits > 0) {
      total += hits;
      offenders.add('$path: $hits');
    }
  }
  expect(
    total,
    lessThanOrEqualTo(_bareLightLiteralCeiling),
    reason: '当前 $total 处：${offenders.join(' / ')}',
  );
}

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

  test('推入式面板自带极性作用域', () {
    for (final path in _mustCarryScope) {
      expect(
        File(path).readAsStringSync().contains('MobileEnvironmentScope'),
        isTrue,
        reason: '$path 由 root navigator 推入，不带作用域就会退回壳层暗基准',
      );
    }
  });

  test('已迁移文件里的裸白字面量不再增长', () {
    _assertBareLightLiterals();
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
