import 'dart:async';

import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

class TaskApi {
  TaskApi(this._client);

  final ApiClient _client;

  Future<List<TaskRecord>> list({int page = 0, int size = 20}) async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/tasks',
      queryParameters: {'page': page, 'size': size},
    );
    final data = response.data;
    if (data == null) return [];
    final items = data['data'] as Map<String, dynamic>?;
    if (items == null) return [];
    final list = items['items'] as List<dynamic>? ?? [];
    return list
        .map((e) => TaskRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 查询当前用户拥有的指定任务。
  Future<TaskRecord> get(String taskId) async {
    final response = await _client.dio.get<Map<String, dynamic>>(
      '/tasks/$taskId',
    );
    final data = response.data?['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw const FormatException('任务详情响应格式不正确');
    }
    return TaskRecord.fromJson(data);
  }

  /// 轮询任务直到进入终态，供需要完成后清理本地缓存的流程使用。
  Future<TaskRecord> waitForTerminal(
    String taskId, {
    Duration timeout = const Duration(minutes: 30),
    Duration interval = const Duration(seconds: 1),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final task = await get(taskId);
      if (task.isTerminal) {
        return task;
      }
      await Future<void>.delayed(interval);
    }
    throw TimeoutException('等待任务完成超时');
  }

  Future<void> retry(String taskId) async {
    // 本人任务重试；死信队列重试走管理端 /admin/tasks。
    await _client.dio.post<Map<String, dynamic>>('/tasks/$taskId/retry');
  }
}
