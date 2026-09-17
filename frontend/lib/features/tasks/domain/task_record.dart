class TaskRecord {
  const TaskRecord({
    required this.id,
    required this.taskType,
    required this.status,
    this.phase,
    this.progress = 0,
    this.resourceType,
    this.resourceId,
    this.routingKey,
    this.result,
    this.errorMessage,
    required this.retryCount,
    required this.maxRetries,
    this.startedAt,
    this.completedAt,
    required this.createdAt,
  });

  factory TaskRecord.fromJson(Map<String, dynamic> json) {
    return TaskRecord(
      id: json['id']?.toString() ?? '',
      taskType: json['type']?.toString() ?? json['taskType']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      phase: json['phase']?.toString(),
      progress: (json['progress'] as num?)?.toInt() ?? 0,
      resourceType: json['resourceType']?.toString(),
      resourceId: json['resourceId']?.toString(),
      routingKey: json['routingKey']?.toString(),
      result: json['result']?.toString(),
      errorMessage:
          json['errorSummary']?.toString() ?? json['errorMessage']?.toString(),
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
      maxRetries: (json['maxRetries'] as num?)?.toInt() ?? 3,
      startedAt: _parseDateTime(json['startedAt']),
      completedAt: _parseDateTime(json['completedAt']),
      createdAt:
          _parseDateTime(json['createdAt']) ??
          _parseDateTime(json['updatedAt']) ??
          DateTime.now(),
    );
  }

  final String id;
  final String taskType;
  final String status;
  final String? phase;
  final int progress;
  final String? resourceType;
  final String? resourceId;
  final String? routingKey;
  final String? result;
  final String? errorMessage;
  final int retryCount;
  final int maxRetries;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime createdAt;

  bool get isPending =>
      status == 'PENDING' || status == 'QUEUED' || status == 'RETRY_WAIT';
  bool get isRunning => status == 'RUNNING';
  bool get isCompleted => status == 'COMPLETED';
  bool get isFailed => status == 'FAILED' || status == 'DLQ';

  /// 本人可重试：仅 FAILED。DLQ 仅管理端可重试。
  bool get canRetry => status == 'FAILED' && retryCount < maxRetries;
  bool get isCancelled => status == 'CANCELLED';
  bool get isTerminal => isCompleted || isFailed || isCancelled;

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    final raw = value.toString();
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) return parsed.toLocal();
    final normalized = raw.replaceFirst(' ', 'T');
    return DateTime.tryParse(normalized)?.toLocal();
  }
}

/// 异步任务提交响应。
class TaskSubmission {
  const TaskSubmission({
    required this.taskId,
    required this.status,
    this.phase,
  });

  factory TaskSubmission.fromJson(Map<String, dynamic> json) {
    return TaskSubmission(
      taskId: json['taskId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'QUEUED',
      phase: json['phase']?.toString(),
    );
  }

  final String taskId;
  final String status;
  final String? phase;
}

/// 全局任务状态条使用的轻量摘要。
class ActiveTaskSummary {
  const ActiveTaskSummary({
    required this.activeCount,
    required this.failedCount,
    this.priorityTask,
  });

  factory ActiveTaskSummary.fromRecords(List<TaskRecord> records) {
    final active = records
        .where((task) => task.isPending || task.isRunning)
        .toList(growable: false);
    final failed = records
        .where((task) => task.isFailed)
        .toList(growable: false);
    final priorityTask =
        failed.firstOrNull ??
        active.where((task) => task.isRunning).firstOrNull ??
        active.firstOrNull;
    return ActiveTaskSummary(
      activeCount: active.length,
      failedCount: failed.length,
      priorityTask: priorityTask,
    );
  }

  final int activeCount;
  final int failedCount;
  final TaskRecord? priorityTask;

  bool get hasActivity => activeCount > 0 || failedCount > 0;
}
