import 'package:omninest/app/widgets/app_dropdown.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/app/theme/feature/video_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/core/widgets/file_purge_confirmation.dart';
import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_models.dart';
import 'package:omninest/features/video/presentation/theme/movie_redesign_theme.dart';
import 'package:omninest/features/video/presentation/widgets/movie_common_widgets.dart';
import 'package:omninest/features/video/presentation/widgets/movie_feedback.dart';
import 'package:omninest/features/video/presentation/widgets/movie_poster_image.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_metadata_edit_drawer.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_empty_state.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_filter_sort_bar.dart';
import 'package:omninest/features/video/presentation/widgets/redesign/movie_redesign_section_header.dart';
import 'package:omninest/core/utils/status_labels.dart';

part 'movie_admin_list.dart';
part 'movie_admin_tasks.dart';
part 'movie_library_access_management.dart';
part 'movie_library_review.dart';
part 'movie_library_management_components.dart';
