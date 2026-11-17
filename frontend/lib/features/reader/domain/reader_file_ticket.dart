/// 阅读源文件的临时下载票据。
class ReaderFileTicket {
  const ReaderFileTicket({
    required this.itemId,
    required this.fileName,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.expiresAt,
    this.sha256,
  });

  final String itemId;
  final String fileName;
  final String downloadUrl;
  final int sizeBytes;
  final String? sha256;
  final DateTime expiresAt;

  factory ReaderFileTicket.fromJson(Map<String, dynamic> json) {
    return ReaderFileTicket(
      itemId: json['itemId']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? 'download',
      downloadUrl: json['downloadUrl']?.toString() ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      sha256: json['sha256']?.toString(),
      expiresAt:
          DateTime.tryParse(json['expiresAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}
