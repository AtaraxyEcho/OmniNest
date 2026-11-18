import 'package:omninest/features/reader/domain/reader_item.dart';

class ReaderDashboard {
  const ReaderDashboard({
    required this.overview,
    required this.continueReading,
    required this.recentItems,
    this.itemsAddedToday = 0,
  });

  factory ReaderDashboard.empty() => ReaderDashboard(
    overview: ReaderOverview.empty(),
    continueReading: const [],
    recentItems: const [],
    itemsAddedToday: 0,
  );

  factory ReaderDashboard.fromJson(Map<String, dynamic> json) {
    return ReaderDashboard(
      overview:
          json['overview'] is Map
              ? ReaderOverview.fromJson(
                Map<String, dynamic>.from(json['overview'] as Map),
              )
              : ReaderOverview.empty(),
      continueReading:
          _asMapList(json['continueReading']).map(ReaderItem.fromJson).toList(),
      recentItems:
          _asMapList(json['recentItems']).map(ReaderItem.fromJson).toList(),
      itemsAddedToday: _asInt(json['itemsAddedToday']),
    );
  }

  final ReaderOverview overview;
  final List<ReaderItem> continueReading;
  final List<ReaderItem> recentItems;
  final int itemsAddedToday;
}

class ReaderOverview {
  const ReaderOverview({
    required this.totalItems,
    required this.continueCount,
    this.dailyReading = const [],
  });

  factory ReaderOverview.empty() =>
      const ReaderOverview(totalItems: 0, continueCount: 0);

  factory ReaderOverview.fromJson(Map<String, dynamic> json) {
    return ReaderOverview(
      totalItems: _asInt(json['totalItems']),
      continueCount: _asInt(json['continueCount']),
      dailyReading:
          _asMapList(
            json['dailyReading'],
          ).map(ReaderDailyReading.fromJson).toList(),
    );
  }

  final int totalItems;
  final int continueCount;

  /// 最近 14 天逐日阅读分钟数（样例概览 `.bars` 柱图的数据源）。
  final List<ReaderDailyReading> dailyReading;
}

/// 单日阅读分钟数；[date] 为 `YYYY-MM-DD`（服务端本地日）。
class ReaderDailyReading {
  const ReaderDailyReading({required this.date, required this.minutes});

  factory ReaderDailyReading.fromJson(Map<String, dynamic> json) {
    return ReaderDailyReading(
      date: json['date']?.toString() ?? '',
      minutes: _asInt(json['minutes']),
    );
  }

  final String date;
  final int minutes;
}

int _asInt(dynamic value) => switch (value) {
  int() => value,
  num() => value.toInt(),
  _ => int.tryParse(value?.toString() ?? '') ?? 0,
};

List<Map<String, dynamic>> _asMapList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}
