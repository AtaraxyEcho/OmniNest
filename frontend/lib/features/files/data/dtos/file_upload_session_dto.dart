import 'package:omninest/features/files/domain/file_upload_session.dart';

class FileUploadPartDto {
  const FileUploadPartDto({
    required this.partNumber,
    required this.sizeBytes,
    required this.status,
    required this.uploadUrl,
    this.eTag,
    this.uploadUrlExpiresAt,
  });

  factory FileUploadPartDto.fromJson(Map<String, dynamic> json) {
    return FileUploadPartDto(
      partNumber: _asInt(json['partNumber']),
      sizeBytes: _asInt(json['sizeBytes']),
      status: json['status']?.toString() ?? 'PENDING',
      eTag: json['eTag']?.toString(),
      uploadUrl: json['uploadUrl']?.toString(),
      uploadUrlExpiresAt:
          DateTime.tryParse(
            json['uploadUrlExpiresAt']?.toString() ?? '',
          )?.toLocal(),
    );
  }

  final int partNumber;
  final int sizeBytes;
  final String status;
  final String? eTag;
  final String? uploadUrl;
  final DateTime? uploadUrlExpiresAt;

  FileUploadPart toDomain() {
    return FileUploadPart(
      partNumber: partNumber,
      sizeBytes: sizeBytes,
      status: status,
      eTag: eTag,
      uploadUrl: uploadUrl,
      uploadUrlExpiresAt: uploadUrlExpiresAt,
    );
  }
}

class FileUploadSessionDto {
  const FileUploadSessionDto({
    required this.id,
    required this.uploadId,
    required this.parentId,
    required this.fileName,
    required this.sizeBytes,
    required this.partSizeBytes,
    required this.totalParts,
    required this.mimeType,
    required this.status,
    required this.uploadUrl,
    required this.parts,
    required this.expiresAt,
  });

  factory FileUploadSessionDto.fromJson(Map<String, dynamic> json) {
    final rawParts = json['parts'];
    return FileUploadSessionDto(
      id: json['id'].toString(),
      uploadId: json['uploadId']?.toString() ?? '',
      parentId: json['parentId']?.toString(),
      fileName: json['fileName']?.toString() ?? '',
      sizeBytes: _asInt(json['sizeBytes']),
      partSizeBytes: _asInt(json['partSizeBytes']),
      totalParts: _asInt(json['totalParts']),
      mimeType: json['mimeType']?.toString() ?? 'application/octet-stream',
      status: json['status']?.toString() ?? 'CREATED',
      uploadUrl: json['uploadUrl']?.toString(),
      parts:
          rawParts is List
              ? rawParts
                  .whereType<Map<String, dynamic>>()
                  .map(FileUploadPartDto.fromJson)
                  .map((dto) => dto.toDomain())
                  .toList()
              : const [],
      expiresAt:
          DateTime.tryParse(json['expiresAt']?.toString() ?? '')?.toLocal(),
    );
  }

  final String id;
  final String uploadId;
  final String? parentId;
  final String fileName;
  final int sizeBytes;
  final int partSizeBytes;
  final int totalParts;
  final String mimeType;
  final String status;
  final String? uploadUrl;
  final List<FileUploadPart> parts;
  final DateTime? expiresAt;

  FileUploadSession toDomain() {
    return FileUploadSession(
      id: id,
      uploadId: uploadId,
      parentId: parentId,
      fileName: fileName,
      sizeBytes: sizeBytes,
      partSizeBytes: partSizeBytes,
      totalParts: totalParts,
      mimeType: mimeType,
      status: status,
      uploadUrl: uploadUrl,
      parts: parts,
      expiresAt: expiresAt,
    );
  }
}

int _asInt(Object? value) {
  return switch (value) {
    final int number => number,
    final num number => number.toInt(),
    final String text => int.tryParse(text) ?? 0,
    _ => 0,
  };
}
