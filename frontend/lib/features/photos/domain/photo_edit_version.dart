/// 照片编辑版本模型
class PhotoEditVersion {
  const PhotoEditVersion({
    required this.id,
    required this.versionNumber,
    required this.editType,
    required this.editParams,
    required this.createdAt,
  });

  final String id;
  final int versionNumber;
  final String editType;
  final Map<String, dynamic> editParams;
  final DateTime? createdAt;

  factory PhotoEditVersion.fromJson(Map<String, dynamic> json) {
    return PhotoEditVersion(
      id: json['id']?.toString() ?? '',
      versionNumber:
          json['versionNumber'] is num
              ? (json['versionNumber'] as num).toInt()
              : int.tryParse(json['versionNumber']?.toString() ?? '') ?? 1,
      editType: json['editType']?.toString() ?? '',
      editParams:
          json['editParams'] is Map
              ? Map<String, dynamic>.from(json['editParams'] as Map)
              : {},
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toLocal(),
    );
  }
}
