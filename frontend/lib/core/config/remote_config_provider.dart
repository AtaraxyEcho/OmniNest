import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/core/config/feature_flags.dart';
import 'package:omninest/core/utils/platform_helper.dart';

/// 全局功能开关 Provider。根据平台自动启用部分功能。
final featureFlagsProvider = Provider<FeatureFlags>((ref) {
  return FeatureFlags(enableDesktopShell: isDesktopPlatform);
});
