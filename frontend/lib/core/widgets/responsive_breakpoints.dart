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
