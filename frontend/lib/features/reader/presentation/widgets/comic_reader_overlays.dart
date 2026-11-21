import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:omninest/app/desktop/widgets/desktop_window_controls.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/mobile_shell/mobile_shell_form.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/utils/platform_helper.dart';
import 'package:omninest/core/widgets/app_slider.dart';
import 'package:omninest/features/reader/domain/comic_models.dart';
import 'package:omninest/features/reader/domain/comic_reader_display_settings.dart';
import 'package:omninest/features/reader/domain/reader_bookmark.dart';
import 'package:omninest/features/reader/presentation/widgets/comic_catalog_tree.dart';
import 'package:omninest/features/reader/presentation/widgets/comic_reader_settings_panel.dart';
import 'package:omninest/features/reader/presentation/widgets/desktop_reader_popover.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_adaptive_panel.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_control_layout.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_panel_coordinator.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_reading_palette.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_shortcut_panel.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_view_settings.dart';
import 'package:omninest/platform/platform_capabilities.dart';

part 'comic_reader_overlays_top_bar.dart';
part 'comic_reader_overlays_bottom_bar.dart';
part 'comic_reader_overlays_panels.dart';
