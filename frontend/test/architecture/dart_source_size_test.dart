import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _maximumSourceLines = 1200;
const _softMaximumSourceLines = 800;

/// 0.1.0 发布前登记的存量超长源码；禁止新增，拆分完成后从清单移除。
const _allowedOversizedSources = <String>{
  'lib/features/music/presentation/deck/music_deck_content.dart',
  'lib/features/reader/presentation/pages/reader_item_detail_page.dart',
  'test/features/music/music_controller_test.dart',
};

/// 已登记的生产源码 800-1200 行存量；禁止新增，拆分完成后从清单移除。
/// 测试代码只受 1200 行硬线约束，不计入软上限登记。
const _allowedSoftOversizedSources = <String>{
  'lib/app/theme/mobile_env_palette.dart',
  'lib/core/widgets/mobile_sample_kit.dart',
  'lib/core/widgets/mobile_ui.dart',
  'lib/features/admin/presentation/pages/admin_operations_logs_center.dart',
  'lib/features/admin/presentation/pages/admin_operations_logs_tasks.dart',
  'lib/features/admin/presentation/pages/admin_users_page.dart',
  'lib/features/admin/presentation/widgets/admin_shell.dart',
  'lib/features/backdrop/presentation/app_backdrop_settings_panel.dart',
  'lib/features/files/application/file_browser_controller.dart',
  'lib/features/files/application/file_browser_upload_actions.dart',
  'lib/features/files/data/file_api.dart',
  'lib/features/files/presentation/pages/file_browser_page.dart',
  'lib/features/files/presentation/pages/file_browser_page_mobile_home.dart',
  'lib/features/files/presentation/pages/file_browser_page_transfer_workspaces.dart',
  'lib/features/files/presentation/pages/file_browser_page_workspace.dart',
  'lib/features/files/presentation/pages/file_preview_page.dart',
  'lib/features/files/presentation/widgets/share_link_sheet.dart',
  'lib/features/library/presentation/widgets/library_space_widgets.dart',
  'lib/features/music/application/music_platform_library_controller.dart',
  'lib/features/music/data/music_api.dart',
  'lib/features/music/presentation/deck/music_deck_content.dart',
  'lib/features/music/presentation/deck/music_deck_content_support.dart',
  'lib/features/music/presentation/deck/music_deck_shell.dart',
  'lib/features/music/presentation/player/music_immersive_controls.dart',
  'lib/features/music/presentation/player/music_immersive_layout_spec.dart',
  'lib/features/music/presentation/player/music_immersive_player_stage.dart',
  'lib/features/music/presentation/player/music_immersive_preset_editor.dart',
  'lib/features/music/presentation/player/music_visual_color_picker.dart',
  'lib/features/notifications/presentation/pages/notification_page.dart',
  'lib/features/photos/application/photo_controller_commands.dart',
  'lib/features/photos/presentation/pages/photo_detail_page.dart',
  'lib/features/photos/presentation/pages/photo_shared_album_page.dart',
  'lib/features/photos/presentation/pages/photo_slideshow_page.dart',
  'lib/features/portal/presentation/widgets/portal_desktop_quick_actions.dart',
  'lib/features/portal/presentation/widgets/portal_mobile_hosted_content.dart',
  'lib/features/portal/presentation/widgets/portal_visual_widgets.dart',
  'lib/features/portal/presentation/widgets/weather_detail_dialog.dart',
  'lib/features/portal/presentation/widgets/weather_detail_sheet.dart',
  'lib/features/reader/application/reader_book_provider.dart',
  'lib/features/reader/data/epub_parser_service.dart',
  'lib/features/reader/data/reader_api.dart',
  'lib/features/reader/data/reader_sync_queue.dart',
  'lib/features/reader/presentation/pages/comic_detail_page.dart',
  'lib/features/reader/presentation/pages/reader_view_page.dart',
  'lib/features/reader/presentation/widgets/book_detail_space.dart',
  'lib/features/reader/presentation/widgets/reader_content_loader.dart',
  'lib/features/reader/presentation/widgets/reader_pagination_engine.dart',
  'lib/features/reader/presentation/widgets/reader_view_page_mixin.dart',
  'lib/features/reader/presentation/widgets/reader_view_settings.dart',
  'lib/features/search/presentation/widgets/global_search_overlay.dart',
  'lib/features/setup/presentation/pages/initial_setup_page.dart',
  'lib/features/video/application/movie_controller.dart',
  'lib/features/video/data/movie_api.dart',
  'lib/features/video/presentation/pages/movie_center_page.dart',
  'lib/features/video/presentation/pages/movie_player_page.dart',
  'lib/features/video/presentation/widgets/movie_admin_list.dart',
};

void main() {
  test('手写 Dart 源码不超过 1200 行', () async {
    final oversizedSources = await _collectOversizedSources(
      roots: const <String>['lib', 'test'],
      maxLines: _maximumSourceLines,
      allowedSources: _allowedOversizedSources,
    );

    expect(
      oversizedSources,
      isEmpty,
      reason: '手写 Dart 源码超过 1200 行，请按职责拆分：\n${oversizedSources.join('\n')}',
    );
  });

  test('生产 Dart 源码超过 800 行必须登记', () async {
    final oversizedSources = await _collectOversizedSources(
      roots: const <String>['lib'],
      maxLines: _softMaximumSourceLines,
      allowedSources: _allowedSoftOversizedSources,
    );

    expect(
      oversizedSources,
      isEmpty,
      reason:
          '生产 Dart 源码超过 800 行且未登记，请先规划拆分并登记存量：\n'
          '${oversizedSources.join('\n')}',
    );
  });
}

Future<List<String>> _collectOversizedSources({
  required List<String> roots,
  required int maxLines,
  required Set<String> allowedSources,
}) async {
  final oversizedSources = <String>[];
  for (final sourceRoot in roots) {
    await for (final entity in Directory(sourceRoot).list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final normalizedPath = entity.path.replaceAll('\\', '/');
      if (_isGeneratedSource(normalizedPath)) {
        continue;
      }
      final lineCount = (await entity.readAsLines()).length;
      if (lineCount > maxLines && !allowedSources.contains(normalizedPath)) {
        oversizedSources.add('$normalizedPath lines=$lineCount');
      }
    }
  }
  oversizedSources.sort();
  return oversizedSources;
}

bool _isGeneratedSource(String path) {
  return path.endsWith('.g.dart') ||
      path.endsWith('.freezed.dart') ||
      path.startsWith('lib/app/l10n/app_localizations');
}
