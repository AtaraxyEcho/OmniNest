/// 照片批量 ZIP 的短期下载票据。
class PhotoBatchDownloadTicket {
  const PhotoBatchDownloadTicket({
    required this.url,
    required this.fileName,
    required this.sizeBytes,
    required this.expiresAt,
    required this.sha256,
  });

  final String url;
  final String fileName;
  final int sizeBytes;
  final DateTime expiresAt;
  final String? sha256;

  factory PhotoBatchDownloadTicket.fromJson(Map<String, dynamic> json) {
    return PhotoBatchDownloadTicket(
      url: json['url']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? 'photos.zip',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      expiresAt:
          DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      sha256: json['sha256']?.toString(),
    );
  }
}
