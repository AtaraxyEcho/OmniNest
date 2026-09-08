import 'package:omninest/features/reader/domain/reader_item.dart';

class ReaderReadingStats {
  const ReaderReadingStats({
    required this.totalMinutesToday,
    required this.totalMinutesThisWeek,
    required this.currentStreak,
    required this.totalBooksRead,
  });

  factory ReaderReadingStats.fromJson(Map<String, dynamic> json) {
    return ReaderReadingStats(
      totalMinutesToday: _asInt(json['totalMinutesToday']),
      totalMinutesThisWeek: _asInt(json['totalMinutesThisWeek']),
      currentStreak: _asInt(json['currentStreak']),
      totalBooksRead: _asInt(json['totalBooksRead']),
    );
  }

  factory ReaderReadingStats.empty() => const ReaderReadingStats(
    totalMinutesToday: 0,
    totalMinutesThisWeek: 0,
    currentStreak: 0,
    totalBooksRead: 0,
  );

  final int totalMinutesToday;
  final int totalMinutesThisWeek;
  final int currentStreak;
  final int totalBooksRead;
}

int _asInt(dynamic value) => switch (value) {
  int() => value,
  num() => value.toInt(),
  _ => int.tryParse(value?.toString() ?? '') ?? 0,
};

/// 每日阅读分钟数（按用户本地时区聚合）。
class ReaderDailyMinutes {
  const ReaderDailyMinutes({required this.date, required this.minutes});

  factory ReaderDailyMinutes.fromJson(Map<String, dynamic> json) {
    return ReaderDailyMinutes(
      date: DateTime.parse(json['date'].toString()),
      minutes: int.tryParse(json['minutes'].toString()) ?? 0,
    );
  }

  final DateTime date;
  final int minutes;
}

/// 阅读统计概览：柱状图数据、完成/在读计数与在读列表。
class ReaderStatsOverview {
  const ReaderStatsOverview({
    required this.dailyMinutes,
    required this.completedCount,
    required this.inProgressCount,
    required this.totalItems,
    required this.inProgressItems,
  });

  factory ReaderStatsOverview.fromJson(Map<String, dynamic> json) {
    final daily =
        (json['dailyMinutes'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ReaderDailyMinutes.fromJson)
            .toList();
    final inProgress =
        (json['inProgressItems'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ReaderItem.fromJson)
            .toList();
    return ReaderStatsOverview(
      dailyMinutes: daily,
      completedCount: int.tryParse(json['completedCount'].toString()) ?? 0,
      inProgressCount: int.tryParse(json['inProgressCount'].toString()) ?? 0,
      totalItems: int.tryParse(json['totalItems'].toString()) ?? 0,
      inProgressItems: inProgress,
    );
  }

  final List<ReaderDailyMinutes> dailyMinutes;
  final int completedCount;
  final int inProgressCount;
  final int totalItems;
  final List<ReaderItem> inProgressItems;
}
