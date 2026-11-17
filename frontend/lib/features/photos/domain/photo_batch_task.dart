/// 照片批量任务
class PhotoBatchTask {
  const PhotoBatchTask({
    required this.id,
    required this.taskType,
    required this.status,
    required this.totalItems,
    required this.processedItems,
    required this.createdAt,
    this.result,
    this.errorMessage,
  });

  final String id;
  final String taskType;
  final String status;
  final int totalItems;
  final int processedItems;
  final String? result;
  final String? errorMessage;
  final DateTime? createdAt;

  factory PhotoBatchTask.fromJson(Map<String, dynamic> json) {
    return PhotoBatchTask(
      id: json['id']?.toString() ?? '',
      taskType: json['taskType']?.toString() ?? '',
      status: json['status']?.toString() ?? 'QUEUED',
      totalItems:
          json['totalItems'] is num ? (json['totalItems'] as num).toInt() : 0,
      processedItems:
          json['processedItems'] is num
              ? (json['processedItems'] as num).toInt()
              : 0,
      result: json['result']?.toString(),
      errorMessage: json['errorMessage']?.toString(),
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal(),
    );
  }

  /// 进度百分比 0.0 ~ 1.0
  double get progress => totalItems > 0 ? processedItems / totalItems : 0.0;

  /// 是否已完成
  bool get isCompleted => status == 'COMPLETED';

  /// 是否失败
  bool get isFailed => status == 'FAILED';

  /// 是否运行中
  bool get isRunning => status == 'RUNNING';
}
