import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _allowedViolations = <String>{
  // admin 媒体库段区按产品决策内嵌视频库源对话框，跨 feature 表现层依赖为受控例外。
  'CROSS_FEATURE_INTERNAL '
      'lib/features/admin/presentation/pages/admin_operations_pages.dart -> '
      'package:omninest/features/video/presentation/widgets/movie_management.dart',
  // 0.1.0 发布前登记的存量架构债，禁止新增，修复后从清单移除。
  'APP_SHELL_FEATURE_INTERNAL lib/app/mobile_shell/mobile_app_shell.dart -> package:omninest/features/photos/presentation/widgets/frame_palette.dart',
  'CROSS_FEATURE_INTERNAL lib/features/files/application/media_import_service.dart -> package:omninest/features/tasks/data/task_api.dart',
  'CROSS_FEATURE_INTERNAL lib/features/music/presentation/deck/music_deck_content.dart -> package:omninest/features/files/presentation/widgets/media_import_button.dart',
  'CROSS_FEATURE_INTERNAL lib/features/portal/presentation/widgets/portal_mobile_shell.dart -> package:omninest/features/reader/presentation/widgets/reader_cover_image.dart',
  // Portal 阅读进度卡与 hosted 内容复用阅读模块认证封面组件。
  'CROSS_FEATURE_INTERNAL lib/features/portal/presentation/widgets/reading_progress_widget.dart -> package:omninest/features/reader/presentation/widgets/reader_cover_image.dart',
  'CROSS_FEATURE_INTERNAL lib/features/profile/presentation/widgets/profile_backup_panel.dart -> package:omninest/features/photos/presentation/widgets/battery_optimization_card.dart',
  'CROSS_FEATURE_INTERNAL lib/features/profile/presentation/widgets/profile_mobile_content.dart -> package:omninest/features/photos/presentation/widgets/battery_optimization_card.dart',
  // 个人中心承载照片备份开关；二次确认与相册选择交互流归 photos 域，跨 feature 表现层复用为受控例外。
  'CROSS_FEATURE_INTERNAL lib/features/profile/presentation/widgets/profile_backup_panel.dart -> package:omninest/features/photos/presentation/widgets/photo_backup_enable_flow.dart',
  'CROSS_FEATURE_INTERNAL lib/features/profile/presentation/widgets/profile_mobile_content.dart -> package:omninest/features/photos/presentation/widgets/photo_backup_enable_flow.dart',
  'OVERSIZED_SOURCE lib/features/music/presentation/deck/music_deck_content.dart lines=1337',
  'OVERSIZED_SOURCE lib/features/reader/presentation/pages/reader_item_detail_page.dart lines=1216',
  'OVERSIZED_SOURCE lib/features/reader/presentation/pages/reader_view_page.dart lines=1286',
  'OVERSIZED_SOURCE lib/features/video/application/movie_controller.dart lines=1274',
  'OVERSIZED_SOURCE lib/features/video/presentation/pages/movie_detail_page.dart lines=1384',
  'PRESENTATION_IMPLEMENTATION_PROVIDER lib/features/profile/presentation/widgets/profile_two_factor_card.dart',
  'PRESENTATION_IMPLEMENTATION_PROVIDER lib/features/reader/presentation/pages/pdf_reader_page.dart',
  'PRESENTATION_IMPLEMENTATION_PROVIDER lib/features/video/presentation/widgets/redesign/movie_metadata_edit_drawer.dart',
};
const _maxProductionSourceLines = 1200;

void main() {
  test('feature 分层、core 依赖和源码规模不得新增违规', () {
    final violations = _scanViolations();
    final unexpected =
        violations.difference(_allowedViolations).toList()..sort();
    final removed = _allowedViolations.difference(violations).toList()..sort();

    expect(unexpected, isEmpty, reason: '发现新增架构违规：\n${unexpected.join('\n')}');
    expect(removed, isEmpty, reason: '以下允许项已修复，请从清单删除：\n${removed.join('\n')}');
  });
}

Set<String> _scanViolations() {
  final violations = <String>{};
  final importPattern = RegExp(r"(?:import|export)\s+'([^']+)'[^;]*;");
  final featurePattern = RegExp(
    r'^package:omninest/features/([^/]+)/(data|presentation)/',
  );

  for (final entity in Directory('lib/features').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }

    final path = entity.path.replaceAll('\\', '/');
    final sourceMatch = RegExp(
      r'lib/features/([^/]+)/(domain|data|application|presentation)/',
    ).firstMatch(path);
    if (sourceMatch == null) {
      continue;
    }

    final sourceFeature = sourceMatch.group(1)!;
    final sourceLayer = sourceMatch.group(2)!;
    final content = entity.readAsStringSync();
    for (final match in importPattern.allMatches(content)) {
      final uri = match.group(1)!;
      if (sourceLayer == 'domain' &&
          (uri.startsWith('package:flutter') ||
              uri.startsWith('package:dio') ||
              featurePattern.hasMatch(uri))) {
        violations.add('DOMAIN_LAYER $path -> $uri');
      }

      if (sourceLayer == 'presentation' &&
          uri.startsWith('package:omninest/features/$sourceFeature/data/')) {
        violations.add('PRESENTATION_DATA $path -> $uri');
      }

      final targetMatch = featurePattern.firstMatch(uri);
      if (targetMatch != null && targetMatch.group(1) != sourceFeature) {
        violations.add('CROSS_FEATURE_INTERNAL $path -> $uri');
      }

      if (sourceFeature == 'portal' &&
          RegExp(
            r'^package:omninest/features/music/'
            r'(application|data|domain|presentation)/',
          ).hasMatch(uri)) {
        violations.add('PORTAL_MUSIC_INTERNAL $path -> $uri');
      }
    }

    if (sourceLayer == 'presentation' &&
        RegExp(r'\bDio\s*\(').hasMatch(content)) {
      violations.add('PRESENTATION_DIO $path');
    }

    if (sourceLayer == 'presentation' &&
        RegExp(
          r'\b(?:apiClientProvider|meApiProvider|movieApiProvider|readerApiProvider|AuthClient\s*\()',
        ).hasMatch(content)) {
      violations.add('PRESENTATION_IMPLEMENTATION_PROVIDER $path');
    }
  }

  for (final entity in Directory('lib/core').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    final path = entity.path.replaceAll('\\', '/');
    final content = entity.readAsStringSync();
    for (final match in importPattern.allMatches(content)) {
      final uri = match.group(1)!;
      if (uri.startsWith('package:omninest/features/')) {
        violations.add('CORE_FEATURE_DEPENDENCY $path -> $uri');
      }
    }
  }

  final shellView = File('lib/app/mobile_shell/mobile_app_shell.dart');
  final shellContent = shellView.readAsStringSync();
  for (final match in importPattern.allMatches(shellContent)) {
    final uri = match.group(1)!;
    if (RegExp(
      r'^package:omninest/features/[^/]+/(application|data|domain|presentation)/',
    ).hasMatch(uri)) {
      violations.add('APP_SHELL_FEATURE_INTERNAL ${shellView.path} -> $uri');
    }
  }

  final portalDashboardProviders = File(
    'lib/features/portal/application/portal_dashboard_providers.dart',
  );
  final portalDashboardContent = portalDashboardProviders.readAsStringSync();
  for (final match in importPattern.allMatches(portalDashboardContent)) {
    final uri = match.group(1)!;
    if (RegExp(
      r'^package:omninest/features/[^/]+/(application|data|domain|presentation)/',
    ).hasMatch(uri)) {
      violations.add(
        'PORTAL_DASHBOARD_FEATURE_INTERNAL '
        '${portalDashboardProviders.path} -> $uri',
      );
    }
  }

  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !_isHandwrittenDartSource(entity)) {
      continue;
    }
    final path = entity.path.replaceAll('\\', '/');
    final lineCount = entity.readAsLinesSync().length;
    if (lineCount > _maxProductionSourceLines) {
      violations.add('OVERSIZED_SOURCE $path lines=$lineCount');
    }
  }

  return violations;
}

bool _isHandwrittenDartSource(File file) {
  final path = file.path.replaceAll('\\', '/');
  if (!path.endsWith('.dart') ||
      path.endsWith('.g.dart') ||
      path.endsWith('.freezed.dart')) {
    return false;
  }
  return !path.startsWith('lib/app/l10n/app_localizations');
}
