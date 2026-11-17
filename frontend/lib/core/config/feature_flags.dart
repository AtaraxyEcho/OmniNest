/// 应用功能开关。通过 [FeatureFlagsProvider] 在 Riverpod 中消费。
class FeatureFlags {
  const FeatureFlags({
    this.enableOfflineMode = true,
    this.enableDesktopShell = false,
  });

  final bool enableOfflineMode;
  final bool enableDesktopShell;

  FeatureFlags copyWith({bool? enableOfflineMode, bool? enableDesktopShell}) {
    return FeatureFlags(
      enableOfflineMode: enableOfflineMode ?? this.enableOfflineMode,
      enableDesktopShell: enableDesktopShell ?? this.enableDesktopShell,
    );
  }
}
