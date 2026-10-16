/// 漫画阅读器独立显示设置。
class ComicReaderDisplaySettings {
  const ComicReaderDisplaySettings({
    required this.readingMode,
    this.fullWidth = false,
    this.contentWidth = 960,
    this.pageGap = 8,
  });

  factory ComicReaderDisplaySettings.fromPreferences(
    Map<String, dynamic> preferences, {
    required String defaultReadingMode,
  }) {
    final rawMode = preferences['comicReadingMode']?.toString();
    final rawWidth =
        (preferences['comicContentWidth'] as num?)?.toDouble() ?? 960;
    final rawGap = (preferences['comicPageGap'] as num?)?.toDouble() ?? 8;
    return ComicReaderDisplaySettings(
      readingMode:
          rawMode == 'page' || rawMode == 'scroll'
              ? rawMode!
              : defaultReadingMode,
      fullWidth: preferences['comicFullWidth'] as bool? ?? false,
      contentWidth: rawWidth.clamp(480, 1440),
      pageGap: rawGap.clamp(0, 24),
    );
  }

  final String readingMode;
  final bool fullWidth;
  final double contentWidth;
  final double pageGap;

  ComicReaderDisplaySettings copyWith({
    String? readingMode,
    bool? fullWidth,
    double? contentWidth,
    double? pageGap,
  }) {
    return ComicReaderDisplaySettings(
      readingMode: readingMode ?? this.readingMode,
      fullWidth: fullWidth ?? this.fullWidth,
      contentWidth: contentWidth ?? this.contentWidth,
      pageGap: pageGap ?? this.pageGap,
    );
  }

  Map<String, dynamic> toPreferences() => {
    'comicReadingMode': readingMode,
    'comicFullWidth': fullWidth,
    'comicContentWidth': contentWidth,
    'comicPageGap': pageGap,
  };
}

/// 合并出一次要落盘的完整偏好字典。
///
/// 只传单键的 `save` 会把整张偏好覆盖成只剩这一项：字号、主题与漫画显示设置一起丢。
/// 显示设置按"已应用 → 防抖中尚未落盘"的顺序写入：防抖那份是用户更新的最后一次
/// 调整，必须盖过内存里那份旧的，否则它落盘时又把用户刚调过的值盖回去。
/// [patch] 最后写入，同一键以本次显式改动为准。
Map<String, dynamic> mergeComicReaderPreferences({
  required Map<String, dynamic> current,
  ComicReaderDisplaySettings? pendingDisplaySettings,
  ComicReaderDisplaySettings? appliedDisplaySettings,
  Map<String, dynamic> patch = const {},
}) {
  return {
    ...current,
    if (appliedDisplaySettings != null)
      ...appliedDisplaySettings.toPreferences(),
    if (pendingDisplaySettings != null)
      ...pendingDisplaySettings.toPreferences(),
    ...patch,
  };
}
