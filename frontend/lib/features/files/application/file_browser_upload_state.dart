part of 'file_browser_controller.dart';

/// 上传冲突待处理项：文件与目标目录必须固化，冲突解决后按原落点重试。
typedef _PendingConflict =
    ({
      SoftDeleteConflict conflict,
      XFile file,
      String fileName,
      int sizeBytes,
      String mimeType,
      UploadTarget target,
    });

/// 排队任务在创建上传会话前被暂停/删除时，恢复上传仍需原始文件与目标快照。
typedef _ResumeTicket =
    ({
      XFile file,
      String fileName,
      int sizeBytes,
      String? mimeType,
      String? asVersionOfFileId,
      UploadTarget target,
    });

/// 上传队列的前置墓碑：Worker 的 prepared 列表与 UI 状态解耦，
/// 删除/暂停必须让轮转到该项的 Worker 看到，否则会重新插回列表继续上传。
mixin _UploadQueueGuards on AsyncNotifier<FileBrowserState> {
  final Set<String> _cancelledLocalTaskIds = <String>{};
  final Set<String> _prePausedLocalTaskIds = <String>{};
  final Map<String, _ResumeTicket> _resumeTickets = <String, _ResumeTicket>{};
}
