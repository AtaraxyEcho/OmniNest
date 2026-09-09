import 'package:dio/dio.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/backdrop/data/app_backdrop_file_picker.dart';

/// 服务端背景素材 DTO(data 层边界,进入仓储后转换为领域模型)。
class BackdropServerAsset {
  const BackdropServerAsset({
    required this.id,
    required this.title,
    required this.mediaType,
    required this.status,
    this.failReason,
    required this.fileSize,
    this.contentUrl,
    this.contentUrlExpiresAt,
    this.thumbUrl,
    this.thumbUrlExpiresAt,
    this.width,
    this.height,
    this.durationMs,
    this.updatedAt,
  });

  factory BackdropServerAsset.fromJson(Map<String, dynamic> json) {
    return BackdropServerAsset(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      mediaType: json['mediaType']?.toString() ?? 'image',
      status: json['status']?.toString() ?? 'PROCESSING',
      failReason: json['failReason']?.toString(),
      fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
      contentUrl: json['contentUrl']?.toString(),
      contentUrlExpiresAt: DateTime.tryParse(
        json['contentUrlExpiresAt']?.toString() ?? '',
      ),
      thumbUrl: json['thumbUrl']?.toString(),
      thumbUrlExpiresAt: DateTime.tryParse(
        json['thumbUrlExpiresAt']?.toString() ?? '',
      ),
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      durationMs: (json['durationMs'] as num?)?.toInt(),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }

  final String id;
  final String title;
  final String mediaType;
  final String status;
  final String? failReason;
  final int fileSize;
  final String? contentUrl;
  final DateTime? contentUrlExpiresAt;
  final String? thumbUrl;
  final DateTime? thumbUrlExpiresAt;
  final int? width;
  final int? height;
  final int? durationMs;
  final DateTime? updatedAt;

  /// 是否处于可被选为当前背景的状态。
  bool get isSelectable => status == 'READY';
}

/// 背景库 API 客户端。
class BackdropApi {
  const BackdropApi(this.apiClient);

  final ApiClient apiClient;

  /// 拉取当前用户的背景素材列表。
  Future<List<BackdropServerAsset>> list() async {
    final response = await apiClient.dio.get<dynamic>('/backdrops');
    final data = _dataOf(response.data);
    return data
        .whereType<Map>()
        .map(
          (item) =>
              BackdropServerAsset.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  /// 删除背景素材。
  Future<void> delete(String assetId) async {
    final response = await apiClient.dio.delete<dynamic>('/backdrops/$assetId');
    _ensureOk(response.data);
  }

  /// 上传背景素材;Web 走流式 multipart,桌面/移动走文件路径。
  Future<BackdropServerAsset> upload(BackdropPickedFile file) async {
    final formData = FormData();
    if (!file.isStreamBased) {
      formData.files.add(
        MapEntry(
          'file',
          await MultipartFile.fromFile(file.path!, filename: file.name),
        ),
      );
    } else {
      if (file.readStream == null) {
        throw const AppException(code: '8002', message: '所选文件不可读');
      }
      formData.files.add(
        MapEntry(
          'file',
          MultipartFile.fromStream(
            () => file.readStream!,
            file.size,
            filename: file.name,
          ),
        ),
      );
    }
    final response = await apiClient.dio.post<dynamic>(
      '/backdrops',
      data: formData,
    );
    final envelope = _ensureOk(response.data);
    final data = envelope['data'];
    if (data is! Map) {
      throw const AppException(
        code: 'BACKDROP_RESPONSE_INVALID',
        message: '背景库响应格式不正确',
      );
    }
    return BackdropServerAsset.fromJson(Map<String, dynamic>.from(data));
  }

  List<dynamic> _dataOf(dynamic body) {
    final envelope = _ensureOk(body);
    final data = envelope['data'];
    return data is List ? data : const [];
  }

  Map<String, dynamic> _ensureOk(dynamic body) {
    final envelope = body is Map ? body : const <String, dynamic>{};
    final code = envelope['code'];
    if (code is num && code.toInt() >= 400) {
      throw AppException(
        code: code.toInt().toString(),
        message: envelope['message']?.toString() ?? '背景库请求失败',
        details:
            envelope['details'] is Map
                ? Map<String, Object?>.from(envelope['details'] as Map)
                : const {},
      );
    }
    return Map<String, dynamic>.from(envelope);
  }
}
