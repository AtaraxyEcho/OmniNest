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
  'lib/core/widgets/env_empty_state.dart',
  'lib/core/widgets/workstation_mobile_sheet.dart',
  'lib/core/auth/login_page.dart',
  'lib/features/music/presentation/pages/music_history_page.dart',
  'lib/features/music/presentation/pages/music_scan_page.dart',
  'lib/features/music/presentation/deck/music_deck_content.dart',
  'lib/features/music/presentation/deck/music_deck_content_support.dart',
  'lib/features/video/presentation/widgets/movie_shell_mobile.dart',
  'lib/features/video/presentation/pages/movie_center_sample_rails.dart',
  'lib/features/video/presentation/widgets/movie_admin_list.dart',
  'lib/features/video/presentation/widgets/movie_history.dart',
  'lib/features/photos/presentation/pages/photos_page_batch_actions.dart',
  'lib/features/photos/presentation/pages/photos_page_view_content.dart',
  'lib/features/photos/presentation/pages/photo_album_detail_page_hosted.dart',
  'lib/features/photos/presentation/pages/photo_album_photo_picker_page.dart',
  'lib/features/photos/presentation/pages/photo_editor_page.dart',
  'lib/features/photos/presentation/pages/photo_groups_page.dart',
  'lib/features/photos/presentation/pages/photo_period_page_hosted.dart',
  'lib/features/reader/presentation/widgets/book_detail_space.dart',
  'lib/features/reader/presentation/widgets/reader_space_content.dart',
];

/// 未接入极性表的 `MobileEnvColors.` 引用出现数（按 allMatches 计；
/// `grep -c` 数行会少算一行多次）。当前 19：壳层 11、`app.dart` 的系统导航条 1、
/// 相册查看器 7（它按 `Theme.brightness` + Photos 模块调色板分支，不属环境角色）。
/// 每接完一个面就把它降到新值；接完之前不给壳层注册极性。
const _remainingCeiling = 19;

/// 经 PopupRoute/Dialog 推入的面板拿不到空间子树的 Theme 注册，
/// 必须自带 MobileEnvironmentScope，否则浅态下整张面板仍是暗值。
const _mustCarryScope = <String>[
  'lib/features/portal/presentation/widgets/weather_detail_sheet.dart',
];

/// 已迁移文件里残留的裸白前景/描边。
///
/// 这些文件已经按 context.env 解析颜色，再出现硬编码白值就意味着浅态不会翻。
/// 压在影像上的字面量（海报徽标、影院 hero 次钮）两极性都不翻，因为对比由图片
/// 本身提供，必须在紧邻上一行标 polarity-stable 并写明原因，否则计入这里。
const _bareLightLiteralCeiling = 0;

/// 已迁移文件里残留的酸绿字面量。强调色在浅态必须换成 accentInk，
/// 残留的 D5F17D 意味着浅态下填充与标签同为不可见；刻意保留的影像浮层
/// 用 polarity-stable 标注，所以这里允许 0。
const _bareAccentLiteralCeiling = 0;

/// 逐行统计命中 pattern 的字面量，跳过上一行标了 polarity-stable 的位置。
List<String> _scanMigratedLiterals(RegExp pattern) {
  final offenders = <String>[];
  for (final path in _migrated) {
    final lines = File(path).readAsStringSync().split('\n');
    var hits = 0;
    for (var index = 0; index < lines.length; index++) {
      final before = index > 0 ? lines[index - 1] : '';
      if (!before.contains('polarity-stable')) {
        hits += pattern.allMatches(lines[index]).length;
      }
    }
    if (hits > 0) {
      offenders.add('$path: $hits');
    }
  }
  return offenders;
}

int _totalOf(List<String> offenders) =>
    offenders.fold(0, (sum, entry) => sum + int.parse(entry.split(': ').last));

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
    final offenders = _scanMigratedLiterals(
      RegExp(r'Colors\.white\b|Color\(0x[0-9A-Fa-f]{2}FFFFFF\)'),
    );
    expect(
      _totalOf(offenders),
      lessThanOrEqualTo(_bareLightLiteralCeiling),
      reason: '当前 ${_totalOf(offenders)} 处：${offenders.join(' / ')}',
    );
  });

  test('已迁移文件里的酸绿字面量清零', () {
    final offenders = _scanMigratedLiterals(
      RegExp(r'Color\(0x[0-9A-Fa-f]{2}D5F17D\)'),
    );
    expect(
      _totalOf(offenders),
      lessThanOrEqualTo(_bareAccentLiteralCeiling),
      reason: '当前 ${_totalOf(offenders)} 处：${offenders.join(' / ')}',
    );
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
