/// 统一响应式断点常量。
///
/// 所有模块共享同一套断点值，避免各模块自定义不同阈值。
class ResponsiveBreakpoints {
  const ResponsiveBreakpoints._();

  /// 手机上限：600px 以下为手机布局。
  static const double mobile = 600;

  /// 平板上限：600-900px 为平板布局。
  static const double tablet = 900;

  /// 桌面下限：900px 以上为桌面布局。
  static const double desktop = 900;

  /// 宽屏下限：1200px 以上使用宽屏优化。
  static const double wide = 1200;

  /// 桌面侧栏画布下限：与桌面端最小窗口宽度一致，非托管内容窄于该值时
  /// 落触屏布局。与 [desktop]（是否切换移动壳层）是两个不同用途的阈值。
  static const double workbenchRail = 1024;

  // ── 移动壳层平板三档（以下为新增项，不改动上方既有阈值）──────────────
  //
  // 逐值对应设计基准 index.css 的三个 `@media` 段落：`(min-width: 600px)`
  // 复用既有 [mobile]，720 与 980 两档新增如下。桌面壳层判定不使用这些
  // 新值，因此与 [tablet]/[desktop]/[workbenchRail] 互不影响。

  /// 舞台限宽档下限：该档起 `.app-frame` 限宽 [stageFrameMaxWidth]、
  /// 内容页边距抬到 [contentHorizontalPadding]、媒体轨道卡片放大。
  static const double stageFrame = 720;

  /// 平板侧栏轨档下限：该档原型出现 `.tablet-rail` 并隐藏底部导航，
  /// Home 转为双栏，内容主栏限宽抬到 [moduleMainWideMaxWidth]。
  static const double tabletRail = 980;

  /// 原型 `.app-frame` 基线最大宽度（窄于 [stageFrame] 时使用）。
  static const double appFrameBaseMaxWidth = 1180;

  /// 原型 `.app-frame` 在 [stageFrame]-[tabletRail] 档的最大宽度。
  static const double stageFrameMaxWidth = 760;

  /// 原型 600-[tabletRail] 档 `.content-scroll` 与 `.app-header` 的居中限宽。
  static const double contentRailMaxWidth = 720;

  /// 原型 `.module-overlay > main` 基线限宽（窄于 [tabletRail] 时使用）。
  static const double moduleMainMaxWidth = 650;

  /// 原型 `.module-overlay > main` 在 [tabletRail] 档以上的限宽。
  static const double moduleMainWideMaxWidth = 760;

  /// 原型 [stageFrame] 档以上 `.content-scroll` 的左右页边距。
  static const double contentHorizontalPadding = 34;

  /// 原型 [stageFrame] 档以上 `.home-stage` 的左右页边距。
  static const double homeHorizontalPadding = 40;

  /// 判断宽度是否落在平板侧栏轨档（[tabletRail] 及以上）。
  static bool showsTabletRail(double width) => width >= tabletRail;

  /// 判断宽度是否落在舞台限宽档（[stageFrame] 至 [tabletRail]）。
  static bool isStageFramed(double width) =>
      width >= stageFrame && width < tabletRail;

  /// 判断宽度是否落在目录/sheet 档（[mobile] 至 [tabletRail]）。
  static bool isTabletBanded(double width) =>
      width >= mobile && width < tabletRail;

  /// 判断是否为手机宽度。
  static bool isMobile(double width) => width < mobile;

  /// 判断是否为平板宽度。
  static bool isTablet(double width) => width >= mobile && width < tablet;

  /// 判断是否为桌面宽度。
  static bool isDesktop(double width) => width >= desktop;

  /// 判断是否为宽屏。
  static bool isWide(double width) => width >= wide;

  /// 判断是否为紧凑布局（移动端）：< 900px
  static bool isCompact(double width) => width < desktop;
}
