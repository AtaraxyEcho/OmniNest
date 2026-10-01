import 'package:omninest/features/files/domain/file_node.dart';

class FileNodeDto {
  const FileNodeDto({
    required this.id,
    required this.parentId,
    required this.name,
    required this.nodeType,
    required this.normalizedPath,
    required this.sizeBytes,
    required this.updatedAt,
    this.mimeType,
    this.spaceType = SpaceType.personal,
    this.uploadedBy,
    this.uploaderName,
    this.coverFileId,
    this.mediaAutoImportTaskId,
  });

  factory FileNodeDto.fromJson(Map<String, dynamic> json) {
    return FileNodeDto(
      id: json['id'].toString(),
      parentId: json['parentId']?.toString(),
      name: json['name']?.toString() ?? '',
      nodeType: json['nodeType']?.toString() ?? 'FILE',
      normalizedPath: json['normalizedPath']?.toString() ?? '/',
      mimeType: json['mimeType']?.toString(),
      sizeBytes: switch (json['sizeBytes']) {
        final int value => value,
        final num value => value.toInt(),
        _ => 0,
      },
      updatedAt:
          DateTime.tryParse(json['updatedAt']?.toString() ?? '')?.toLocal(),
      spaceType: SpaceType.fromValue(
        json['spaceType']?.toString() ?? 'PERSONAL',
      ),
      uploadedBy: json['uploadedBy']?.toString(),
      uploaderName: json['uploadedByName']?.toString(),
      coverFileId: json['coverFileId']?.toString(),
      mediaAutoImportTaskId: json['mediaAutoImportTaskId']?.toString(),
    );
  }

  final String id;
  final String? parentId;
  final String name;
  final String nodeType;
  final String normalizedPath;
  final String? mimeType;
  final int sizeBytes;
  final DateTime? updatedAt;
  final SpaceType spaceType;
  final String? uploadedBy;
  final String? uploaderName;
  final String? coverFileId;
  final String? mediaAutoImportTaskId;

  FileNode toDomain() {
    return FileNode(
      id: id,
      parentId: parentId,
      name: name,
      isFolder: nodeType == 'FOLDER',
      nodeType: nodeType,
      normalizedPath: normalizedPath,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      updatedAt: updatedAt,
      spaceType: spaceType,
      uploadedBy: uploadedBy,
      uploaderName: uploaderName,
      coverFileId: coverFileId,
      mediaAutoImportTaskId: mediaAutoImportTaskId,
    );
  }
}
