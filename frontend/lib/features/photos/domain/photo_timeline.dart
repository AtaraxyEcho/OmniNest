import 'package:omninest/features/photos/domain/photo.dart';

/// 照片时间线数据
class PhotoTimeline {
  const PhotoTimeline({required this.years});

  final List<PhotoYearGroup> years;

  factory PhotoTimeline.fromJson(Map<String, dynamic> json) {
    return PhotoTimeline(
      years:
          (json['years'] as List?)
              ?.whereType<Map>()
              .map((e) => PhotoYearGroup.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
    );
  }

  /// 从扁平月份条目构建按年份分组的时间线。
  factory PhotoTimeline.fromMonthEntries(
    Iterable<PhotoTimelineMonthEntry> entries,
  ) {
    final monthsByYear = <int, List<PhotoMonthGroup>>{};
    for (final entry in entries) {
      monthsByYear.putIfAbsent(entry.year, () => []).add(entry.monthGroup);
    }
    return PhotoTimeline(
      years: monthsByYear.entries
          .map(
            (entry) => PhotoYearGroup(
              year: entry.key,
              months: List.unmodifiable(entry.value),
            ),
          )
          .toList(growable: false),
    );
  }

  /// 按当前展示顺序返回扁平月份条目。
  List<PhotoTimelineMonthEntry> get monthEntries => [
    for (final year in years)
      for (final month in year.months)
        PhotoTimelineMonthEntry(year: year.year, monthGroup: month),
  ];

  int get monthCount =>
      years.fold(0, (total, year) => total + year.months.length);
}

/// 时间线中的单个月份条目。
class PhotoTimelineMonthEntry {
  const PhotoTimelineMonthEntry({required this.year, required this.monthGroup});

  final int year;
  final PhotoMonthGroup monthGroup;

  String get key => '$year-${monthGroup.month}';

  factory PhotoTimelineMonthEntry.fromJson(Map<String, dynamic> json) {
    return PhotoTimelineMonthEntry(
      year: json['year'] is num ? (json['year'] as num).toInt() : 0,
      monthGroup: PhotoMonthGroup.fromJson(json),
    );
  }
}

/// 照片时间线月份分页。
class PhotoTimelinePage {
  const PhotoTimelinePage({
    required this.items,
    required this.page,
    required this.size,
    required this.totalElements,
    required this.totalPages,
  });

  final List<PhotoTimelineMonthEntry> items;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;

  factory PhotoTimelinePage.fromJson(Map<String, dynamic> json) {
    return PhotoTimelinePage(
      items:
          (json['items'] as List?)
              ?.whereType<Map>()
              .map(
                (item) => PhotoTimelineMonthEntry.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList(growable: false) ??
          const [],
      page: json['page'] is num ? (json['page'] as num).toInt() : 0,
      size: json['size'] is num ? (json['size'] as num).toInt() : 50,
      totalElements:
          json['totalElements'] is num
              ? (json['totalElements'] as num).toInt()
              : 0,
      totalPages:
          json['totalPages'] is num ? (json['totalPages'] as num).toInt() : 0,
    );
  }
}

/// 年份分组
class PhotoYearGroup {
  const PhotoYearGroup({required this.year, required this.months});

  final int year;
  final List<PhotoMonthGroup> months;

  factory PhotoYearGroup.fromJson(Map<String, dynamic> json) {
    return PhotoYearGroup(
      year: json['year'] is num ? (json['year'] as num).toInt() : 0,
      months:
          (json['months'] as List?)
              ?.whereType<Map>()
              .map(
                (e) => PhotoMonthGroup.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList() ??
          [],
    );
  }
}

/// 月份分组
class PhotoMonthGroup {
  const PhotoMonthGroup({
    required this.month,
    required this.photoCount,
    required this.previewPhotos,
  });

  final int month;
  final int photoCount;
  final List<PhotoItem> previewPhotos;

  factory PhotoMonthGroup.fromJson(Map<String, dynamic> json) {
    return PhotoMonthGroup(
      month: json['month'] is num ? (json['month'] as num).toInt() : 0,
      photoCount:
          json['photoCount'] is num ? (json['photoCount'] as num).toInt() : 0,
      previewPhotos:
          (json['previewPhotos'] as List?)
              ?.whereType<Map>()
              .map((e) => PhotoItem.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
    );
  }
}
