import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/errors/error_codes.dart';

/// 上传完成受理结果。
///
/// 受理后状态为 SCANNING 时文件节点尚未创建，需等待安全扫描任务终态后
/// 从任务结果中读取 fileNodeId；COMPLETED 表示文件已入库（重复完成请求的幂等返回）。
class FileUploadCompleteResult {
  const FileUploadCompleteResult({
    required this.uploadId,
    required this.status,
    this.taskId,
    this.fileNodeId,
  });

  factory FileUploadCompleteResult.fromJson(Map<String, dynamic> json) {
    return FileUploadCompleteResult(
      uploadId: json['uploadId']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      taskId: json['taskId']?.toString(),
      fileNodeId: json['fileNodeId']?.toString(),
    );
  }

  final String uploadId;
  final String status;
  final String? taskId;
  final String? fileNodeId;

  bool get isScanning => status == 'SCANNING';

  /// 安全扫描未通过或重试耗尽。
  AppException scanFailedException(String? detail) => AppException(
    code: AppErrorCodes.securityScanFailed,
    message: detail ?? AppErrorCodes.securityScanFailed,
  );
}
