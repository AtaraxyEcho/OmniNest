import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:omninest/app/l10n/app_localizations.dart';
import 'package:omninest/app/theme/app_typography.dart';
import 'package:omninest/core/theme/motion_token.dart';
import 'package:omninest/core/widgets/app_slider.dart';
import 'package:omninest/core/widgets/responsive_breakpoints.dart';
import 'package:omninest/app/theme/feature/admin_colors.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/features/admin/application/admin_operations_controller.dart';
import 'package:omninest/features/admin/domain/admin_operations.dart';
import 'package:omninest/features/admin/domain/admin_paging.dart';
import 'package:omninest/features/admin/domain/admin_user.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_common_widgets.dart';

/// 页面入场动画包装器 — 给定 children 列表，自动施加交错 fade+slide 入场。

import 'package:omninest/features/video/application/movie_controller.dart';
import 'package:omninest/features/video/domain/movie_management_models.dart';
import 'package:omninest/core/utils/status_labels.dart';
import 'package:omninest/features/video/presentation/widgets/movie_management.dart';
import 'package:omninest/features/admin/presentation/widgets/admin_list_components.dart';
import 'package:omninest/features/admin/application/admin_log_csv.dart';
part 'admin_operations_monitoring.dart';
part 'admin_operations_logs_tasks.dart';
part 'admin_operations_logs_center.dart';
part 'admin_operations_roles.dart';
part 'admin_operations_roles_config.dart';
part 'admin_operations_config_labels.dart';
part 'admin_operations_storage.dart';
part 'admin_operations_external_storage.dart';
part 'admin_operations_library.dart';
part 'admin_operations_sessions.dart';
