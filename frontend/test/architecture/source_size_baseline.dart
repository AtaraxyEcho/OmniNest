/// 已登记长文件的当前行数上限（棘轮）。
///
/// 只允许下调：文件继续变大时先按职责拆分，拆分后删除或收紧对应条目。
/// 新增超过 800 行的生产源码必须在此登记，登记即锁定当前行数。
const sourceLineCaps = <String, int>{
  'lib/app/desktop/pages/desktop_files_dialogs.dart': 860,
  'lib/app/desktop/pages/desktop_files_table.dart': 923,
  'lib/app/desktop/pages/desktop_movies_cards.dart': 950,
  'lib/app/desktop/pages/desktop_music_page.dart': 975,
  'lib/app/desktop/pages/desktop_music_platform.dart': 837,
  'lib/app/desktop/pages/desktop_now_playing_deck.dart': 885,
  'lib/app/desktop/pages/desktop_photo_viewer_page.dart': 1090,
  'lib/app/desktop/pages/desktop_photos_justified.dart': 1013,
  'lib/app/desktop/pages/desktop_reader_page.dart': 897,
  'lib/app/desktop/pages/desktop_series_detail_sections.dart': 809,
  'lib/app/desktop/pages/desktop_settings_more.dart': 837,
  'lib/app/desktop/pages/desktop_setup_page.dart': 997,
  'lib/app/desktop/widgets/desktop_media_import_dialog.dart': 838,
  'lib/app/desktop/widgets/desktop_places_globe.dart': 1087,
  'lib/app/desktop/widgets/desktop_surfaces.dart': 989,
  'lib/app/router.dart': 1001,
  'lib/app/theme/mobile_env_palette.dart': 811,
  'lib/core/widgets/mobile_sample_kit.dart': 847,
  'lib/features/admin/presentation/pages/admin_operations_logs_center.dart':
      956,
  'lib/features/admin/presentation/pages/admin_operations_logs_tasks.dart': 898,
  'lib/features/admin/presentation/pages/admin_operations_roles.dart': 876,
  'lib/features/admin/presentation/pages/admin_operations_storage_desktop.dart':
      858,
  'lib/features/admin/presentation/pages/admin_user_dialogs.dart': 943,
  'lib/features/admin/presentation/pages/admin_users_page.dart': 910,
  'lib/features/admin/presentation/widgets/admin_shell.dart': 805,
  'lib/features/backdrop/presentation/app_backdrop_settings_panel.dart': 839,
  'lib/features/files/application/file_browser_controller.dart': 963,
  'lib/features/library/presentation/widgets/library_space_widgets.dart': 863,
  'lib/features/music/application/music_platform_library_controller.dart': 944,
  'lib/features/music/application/music_playback_session.dart': 872,
  'lib/features/music/data/music_api.dart': 830,
  'lib/features/music/presentation/deck/music_deck_content_support.dart': 832,
  'lib/features/music/presentation/deck/music_deck_shell.dart': 933,
  'lib/features/music/presentation/player/music_immersive_controls.dart': 822,
  'lib/features/music/presentation/player/music_immersive_layout_spec.dart':
      950,
  'lib/features/music/presentation/player/music_immersive_player_stage.dart':
      848,
  'lib/features/music/presentation/player/music_visual_color_picker.dart': 837,
  'lib/features/music/presentation/widgets/music_metadata_edit_dialog.dart':
      905,
  'lib/features/photos/application/photo_controller_commands.dart': 925,
  'lib/features/photos/data/photo_api.dart': 827,
  'lib/features/portal/presentation/widgets/portal_desktop_quick_actions.dart':
      851,
  'lib/features/portal/presentation/widgets/weather_detail_dialog.dart': 937,
  'lib/features/portal/presentation/widgets/weather_detail_sheet.dart': 881,
  'lib/features/reader/application/reader_book_provider.dart': 911,
  'lib/features/reader/data/epub_parser_service.dart': 833,
  'lib/features/reader/presentation/pages/comic_detail_page.dart': 831,
  'lib/features/reader/presentation/pages/reader_metadata_edit_page.dart': 896,
  'lib/features/reader/presentation/pages/reader_view_page.dart': 813,
  'lib/features/reader/presentation/widgets/book_detail_space.dart': 847,
  'lib/features/reader/presentation/widgets/comic_reader_settings_panel.dart':
      887,
  'lib/features/reader/presentation/widgets/comic_reader_view.dart': 1007,
  'lib/features/reader/presentation/widgets/comic_reader_view_sections.dart':
      899,
  'lib/features/reader/presentation/widgets/reader_content_loader.dart': 703,
  'lib/features/reader/presentation/widgets/reader_pagination_engine.dart': 904,
  'lib/features/reader/presentation/widgets/reader_view_content.dart': 640,
  'lib/features/reader/presentation/widgets/reader_view_page_mixin.dart': 807,
  'lib/features/reader/presentation/widgets/reader_view_settings.dart': 540,
  'lib/features/video/presentation/pages/movie_player_page.dart': 822,
  'lib/features/video/presentation/widgets/movie_player_sheets.dart': 888,
};

/// 生成文件不参与源码尺寸与棘轮统计。
bool isGeneratedDartSource(String path) {
  return path.endsWith('.g.dart') ||
      path.endsWith('.freezed.dart') ||
      path.startsWith('lib/app/l10n/app_localizations');
}
