class AdminAnalytics {
  const AdminAnalytics({
    required this.userGrowth,
    required this.taskThroughput,
    required this.storageGrowth,
    required this.currentLoad,
  });

  factory AdminAnalytics.fromJson(Map<String, dynamic> json) {
    return AdminAnalytics(
      userGrowth: _dailyMetrics(json['userGrowth']),
      taskThroughput: _taskMetrics(json['taskThroughput']),
      storageGrowth: _dailyMetrics(json['storageGrowth']),
      currentLoad: SystemLoadSnapshot.fromJson(_map(json['currentLoad'])),
    );
  }

  final List<DailyMetric> userGrowth;
  final List<DailyTaskMetric> taskThroughput;
  final List<DailyMetric> storageGrowth;
  final SystemLoadSnapshot currentLoad;
}

class DailyMetric {
  const DailyMetric({required this.date, required this.value});

  factory DailyMetric.fromJson(Map<String, dynamic> json) {
    return DailyMetric(
      date: json['date']?.toString() ?? '',
      value: _intValue(json['value']),
    );
  }

  final String date;
  final int value;
}

class DailyTaskMetric {
  const DailyTaskMetric({
    required this.date,
    required this.completed,
    required this.failed,
    required this.running,
  });

  factory DailyTaskMetric.fromJson(Map<String, dynamic> json) {
    return DailyTaskMetric(
      date: json['date']?.toString() ?? '',
      completed: _intValue(json['completed']),
      failed: _intValue(json['failed']),
      running: _intValue(json['running']),
    );
  }

  final String date;
  final int completed;
  final int failed;
  final int running;
}

class SystemLoadSnapshot {
  const SystemLoadSnapshot({
    required this.cpuUsage,
    required this.memoryUsage,
    required this.diskUsage,
    required this.jvmHeapUsage,
  });

  factory SystemLoadSnapshot.fromJson(Map<String, dynamic> json) {
    return SystemLoadSnapshot(
      cpuUsage: _doubleValue(json['cpuUsage']),
      memoryUsage: _doubleValue(json['memoryUsage']),
      diskUsage: _doubleValue(json['diskUsage']),
      jvmHeapUsage: _doubleValue(json['jvmHeapUsage']),
    );
  }

  final double cpuUsage;
  final double memoryUsage;
  final double diskUsage;
  final double jvmHeapUsage;
}

Map<String, dynamic> _map(Object? value) =>
    value is Map<String, dynamic> ? value : <String, dynamic>{};

List<DailyMetric> _dailyMetrics(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map<String, dynamic>>()
      .map(DailyMetric.fromJson)
      .toList();
}

List<DailyTaskMetric> _taskMetrics(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map<String, dynamic>>()
      .map(DailyTaskMetric.fromJson)
      .toList();
}

int _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _doubleValue(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
