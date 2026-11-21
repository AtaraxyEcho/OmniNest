/// 漫画阅读器独立显示设置。
class ComicReaderDisplaySettings {
  const ComicReaderDisplaySettings({
    required this.readingMode,
    this.fullWidth = false,
    this.contentWidth = 960,
    this.pageGap = 8,
    this.dualPage = false,
    this.rtlOverride,
    this.imageFit = 'contain',
  });

  factory ComicReaderDisplaySettings.fromPreferences(
    Map<String, dynamic> preferences, {
    required String defaultReadingMode,
    String? itemId,
  }) {
    final rawMode = preferences['comicReadingMode']?.toString();
    final normalizedMode = switch (rawMode) {
      'book' => 'book',
      'page' || 'swipe' => 'page',
      'scroll' => 'scroll',
      _ => defaultReadingMode,
    };
    final rawWidth =
        (preferences['comicContentWidth'] as num?)?.toDouble() ?? 960;
    final rawGap = (preferences['comicPageGap'] as num?)?.toDouble() ?? 8;
    final rawFit = preferences['comicImageFit']?.toString();
    final normalizedFit =
        (rawFit == 'contain' || rawFit == 'fitWidth' || rawFit == 'fitHeight')
            ? rawFit!
            : 'contain';
    bool? rtlOverride;
    final rawRtlMap = preferences['comicRtlByItem'];
    if (itemId != null && rawRtlMap is Map && rawRtlMap[itemId] is bool) {
      rtlOverride = rawRtlMap[itemId] as bool;
    }
    return ComicReaderDisplaySettings(
      readingMode: normalizedMode,
      fullWidth: preferences['comicFullWidth'] as bool? ?? false,
      contentWidth: rawWidth.clamp(480, 1440),
      pageGap: rawGap.clamp(0, 24),
      dualPage: preferences['comicDualPage'] as bool? ?? false,
      rtlOverride: rtlOverride,
      imageFit: normalizedFit,
    );
  }

  /// 阅读模式：`book`（3D 仿真翻页）、`page`（水平滑动 Swipe）、`scroll`（竖向卷轴）。
  final String readingMode;
  final bool fullWidth;
  final double contentWidth;
  final double pageGap;

  /// 双页跨页浏览开关（对齐样例 `ReaderView.tsx:359`）。
  final bool dualPage;

  /// 单本漫画阅读方向覆写（true = RTL 日漫右翻左，null = 跟随清单默认）。
  final bool? rtlOverride;

  /// 图片适应模式：`contain`（适应屏幕）、`fitWidth`（适应宽度）、`fitHeight`（适应高度）。
  final String imageFit;

  ComicReaderDisplaySettings copyWith({
    String? readingMode,
    bool? fullWidth,
    double? contentWidth,
    double? pageGap,
    bool? dualPage,
    bool? rtlOverride,
    bool clearRtlOverride = false,
    String? imageFit,
  }) {
    return ComicReaderDisplaySettings(
      readingMode: readingMode ?? this.readingMode,
      fullWidth: fullWidth ?? this.fullWidth,
      contentWidth: contentWidth ?? this.contentWidth,
      pageGap: pageGap ?? this.pageGap,
      dualPage: dualPage ?? this.dualPage,
      rtlOverride: clearRtlOverride ? null : (rtlOverride ?? this.rtlOverride),
      imageFit: imageFit ?? this.imageFit,
    );
  }

  Map<String, dynamic> toPreferences({
    String? itemId,
    Map<String, dynamic>? existingRtlMap,
  }) {
    final nextRtlMap = <String, dynamic>{...?existingRtlMap};
    if (itemId != null && rtlOverride != null) {
      nextRtlMap[itemId] = rtlOverride;
    }
    return {
      'comicReadingMode': readingMode,
      'comicFullWidth': fullWidth,
      'comicContentWidth': contentWidth,
      'comicPageGap': pageGap,
      'comicDualPage': dualPage,
      'comicImageFit': imageFit,
      if (nextRtlMap.isNotEmpty) 'comicRtlByItem': nextRtlMap,
    };
  }
}

/// 合并出一次要落盘的完整偏好字典。
///
/// 只传单键的 `save` 会把整张偏好覆盖成只剩这一项：字号、主题与漫画显示设置一起丢。
/// 显示设置按"已应用 → 防抖中尚未落盘"的顺序写入：防抖那份是用户更新的最后一次
/// 调整，必须盖过内存里那份旧的，否则它落盘时又把用户刚调过的值盖回去。
/// 同步保留完整的 `comicRtlByItem` 映射，避免单本 RTL 偏好在序列化合并时丢失。
/// [patch] 最后写入，同一键以本次显式改动为准。
Map<String, dynamic> mergeComicReaderPreferences({
  required Map<String, dynamic> current,
  ComicReaderDisplaySettings? pendingDisplaySettings,
  ComicReaderDisplaySettings? appliedDisplaySettings,
  Map<String, dynamic> patch = const {},
  String? itemId,
}) {
  final mergedRtl = <String, dynamic>{};
  final rawCurrentRtl = current['comicRtlByItem'];
  if (rawCurrentRtl is Map) {
    for (final entry in rawCurrentRtl.entries) {
      mergedRtl[entry.key.toString()] = entry.value;
    }
  }

  Map<String, dynamic> serialize(ComicReaderDisplaySettings settings) {
    final prefs = settings.toPreferences(
      itemId: itemId,
      existingRtlMap: mergedRtl,
    );
    final updatedRtl = prefs['comicRtlByItem'];
    if (updatedRtl is Map) {
      mergedRtl
        ..clear()
        ..addAll({
          for (final entry in updatedRtl.entries)
            entry.key.toString(): entry.value,
        });
    }
    return prefs;
  }

  final appliedPrefs =
      appliedDisplaySettings == null ? null : serialize(appliedDisplaySettings);
  final pendingPrefs =
      pendingDisplaySettings == null ? null : serialize(pendingDisplaySettings);

  final patchRtl = patch['comicRtlByItem'];
  if (patchRtl is Map) {
    for (final entry in patchRtl.entries) {
      mergedRtl[entry.key.toString()] = entry.value;
    }
  }

  return {
    ...current,
    if (appliedPrefs != null) ...appliedPrefs,
    if (pendingPrefs != null) ...pendingPrefs,
    ...patch,
    if (mergedRtl.isNotEmpty) 'comicRtlByItem': mergedRtl,
  };
}
