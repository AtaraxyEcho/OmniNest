/// 非 Web 平台的占位实现。
String? getBrowserOrigin() => null;

/// 非 Web 平台没有站点内路径概念，前缀恒为根。
String getPageBasePath() => '/';
