// 极性落地后的三条常驻守卫：已接入极性表的文件里不许再出现裸白前景与裸酸绿
// 强调字面量（浅态不翻），推入式面板必须自带极性作用域。
// 原先还有两条守「不得引用 MobileEnvColors」的断言，那个单极性常量类已删，
// 引用它连编译都过不了，所以不必再守。
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
  'lib/features/music/presentation/widgets/music_mobile_mini_player_slot.dart',
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
  'lib/app/mobile_shell/mobile_app_shell.dart',
  'lib/app/app.dart',
];

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

/// 危险色只有一个来源：`MobileEnvPalette.statusDanger`（暗 #E69696 / 浅 #BA1A1A）。
/// 手抄字面量的历史值是 #E2A1A1 一族，它在浅纸上约 2.3:1，删除/退出这类高危动作
/// 在浅色模式下会看不清。
const _dangerLiteralCeiling = 0;

/// 允许出现这些色值的落点：调色板本体，以及自带 OnPaper 同位表的功能编码。
const _dangerLiteralAllowed = <String>[
  'lib/features/files/presentation/widgets/file_env_glyph.dart',
];

/// 墨色也只有角色可用：`ink`/`inkMuted`/`inkFaint` 在两极性各自成值，
/// 手抄其中一档（搜索页曾抄走摄影档的 0x9E 前缀）就意味着浅态不翻色。
const _inkLiteralCeiling = 0;

/// 阅读面板自带一套按亮度三元取值的双值表，不吃空间极性表。
const _inkLiteralAllowed = <String>[
  'lib/features/reader/presentation/widgets/reader_view_settings.dart',
];

/// 全 lib 扫描字面量，跳过调色板本体与逐个说明过的例外落点。
List<String> _scanLiteralFamily(RegExp pattern, List<String> allowed) {
  final offenders = <String>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    final path = entity.path.replaceAll('\\', '/');
    // 调色板本体就是这些色值的定义处。
    if (path.startsWith('lib/app/theme/') || allowed.contains(path)) {
      continue;
    }
    final hits = pattern.allMatches(entity.readAsStringSync()).length;
    if (hits > 0) {
      offenders.add('$path: $hits');
    }
  }
  return offenders;
}

List<String> _scanDangerLiterals() => _scanLiteralFamily(
  RegExp(
    r'Color\(\s*0x(?:[0-9A-Fa-f]{2})?(?:E2A1A1|E69696|BA1A1A)\s*\)',
    caseSensitive: false,
  ),
  _dangerLiteralAllowed,
);

List<String> _scanInkLiterals() => _scanLiteralFamily(
  RegExp(r'Color\(0x[0-9A-Fa-f]{2}(?:F6F6F2|F4F7F1)\)'),
  _inkLiteralAllowed,
);

void main() {
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

  test('危险色不手抄字面量，一律取 statusDanger 角色', () {
    final offenders = _scanDangerLiterals();
    expect(
      offenders.fold(
        0,
        (sum, entry) => sum + int.parse(entry.split(': ').last),
      ),
      lessThanOrEqualTo(_dangerLiteralCeiling),
      reason:
          '出现手抄的危险色，浅态不会翻色，请改用 context.env.statusDanger：'
          '${offenders.join(' / ')}',
    );
  });

  test('墨色不手抄字面量，一律取 ink 三档角色', () {
    final offenders = _scanInkLiterals();
    expect(
      _totalOf(offenders),
      lessThanOrEqualTo(_inkLiteralCeiling),
      reason:
          '出现手抄的墨色，浅态不会翻色，请改用 context.env.ink/inkMuted/inkFaint：'
          '${offenders.join(' / ')}',
    );
  });
}
