/// 可续传文件下载所需的稳定对象元数据。
class ResumableFileTicket {
  const ResumableFileTicket({
    required this.downloadUrl,
    required this.sizeBytes,
    required this.errorCodePrefix,
    required this.fileLabel,
    this.sha256,
  });

  final String downloadUrl;
  final int sizeBytes;
  final String? sha256;
  final String errorCodePrefix;
  final String fileLabel;

  /// 生成调用模块拥有的稳定错误码。
  String errorCode(String suffix) => '${errorCodePrefix}_$suffix';
}
