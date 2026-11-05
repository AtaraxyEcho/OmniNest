/// 已登记长文件的当前行数上限（棘轮）。
///
/// 只允许下调：文件继续变大时先按职责拆分，拆分后删除或收紧对应条目。
/// 新增超过 800 行的生产源码必须在此登记，登记即锁定当前行数。
const sourceLineCaps = <String, int>{
  'lib/app/theme/mobile_env_palette.dart': 811,
  'lib/core/widgets/mobile_sample_kit.dart': 847,
  'lib/features/admin/presentation/pages/admin_operations_logs_center.dart':
      921,
  'lib/features/admin/presentation/pages/admin_users_page.dart': 910,
  'lib/features/admin/presentation/widgets/admin_shell.dart': 825,
  'lib/features/backdrop/presentation/app_backdrop_settings_panel.dart': 903,
  'lib/features/files/application/file_browser_controller.dart': 789,
  'lib/features/files/application/file_browser_upload_actions.dart': 425,
  'lib/features/files/presentation/pages/file_browser_page_transfer_workspaces.dart':
      669,
  'lib/features/files/presentation/pages/file_preview_page.dart': 807,
  'lib/features/files/presentation/widgets/share_link_sheet.dart': 683,
  'lib/features/library/presentation/widgets/library_space_widgets.dart': 863,
  'lib/features/music/application/music_platform_library_controller.dart': 944,
  'lib/features/music/data/music_api.dart': 857,
  'lib/features/music/presentation/deck/music_deck_content_support.dart': 832,
  'lib/features/music/presentation/deck/music_deck_shell.dart': 933,
  'lib/features/music/presentation/player/music_immersive_controls.dart': 822,
  'lib/features/music/presentation/player/music_immersive_layout_spec.dart':
      950,
  'lib/features/music/presentation/player/music_immersive_player_stage.dart':
      848,
  'lib/features/music/presentation/player/music_visual_color_picker.dart': 837,
  'lib/features/notifications/presentation/pages/notification_page.dart': 478,
  'lib/features/photos/application/photo_controller_commands.dart': 925,
  'lib/features/photos/presentation/pages/photo_detail_page.dart': 788,
  'lib/features/photos/presentation/pages/photo_shared_album_page.dart': 597,
  'lib/features/photos/presentation/pages/photo_slideshow_page.dart': 797,
  'lib/features/portal/presentation/widgets/portal_desktop_quick_actions.dart':
      850,
  'lib/features/portal/presentation/widgets/weather_detail_dialog.dart': 937,
  'lib/features/portal/presentation/widgets/weather_detail_sheet.dart': 881,
  'lib/features/reader/application/reader_book_provider.dart': 911,
  'lib/features/reader/data/epub_parser_service.dart': 833,
  'lib/features/reader/data/reader_api.dart': 788,
  'lib/features/reader/data/reader_sync_queue.dart': 741,
  'lib/features/reader/presentation/pages/comic_detail_page.dart': 831,
  'lib/features/reader/presentation/pages/reader_view_page.dart': 818,
  'lib/features/reader/presentation/widgets/book_detail_space.dart': 839,
  'lib/features/reader/presentation/widgets/reader_content_loader.dart': 814,
  'lib/features/reader/presentation/widgets/reader_pagination_engine.dart': 904,
  'lib/features/reader/presentation/widgets/reader_view_page_mixin.dart': 807,
  'lib/features/setup/presentation/pages/initial_setup_page.dart': 690,
  'lib/features/video/presentation/pages/movie_player_page.dart': 919,
  'lib/features/video/presentation/widgets/movie_admin_list.dart': 774,
};

/// 生成文件不参与源码尺寸与棘轮统计。
bool isGeneratedDartSource(String path) {
  return path.endsWith('.g.dart') ||
      path.endsWith('.freezed.dart') ||
      path.startsWith('lib/app/l10n/app_localizations');
}
