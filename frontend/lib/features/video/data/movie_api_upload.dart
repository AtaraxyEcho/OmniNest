part of 'movie_api.dart';

/// 上传会话与预签名写入。
mixin MovieApiUpload on MovieApiBase {
  Future<UploadSession> createUploadSession({
    required String fileName,
    required int sizeBytes,
    String? mimeType,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/uploads/sessions',
      data: {
        'fileName': fileName,
        'sizeBytes': sizeBytes,
        if (mimeType != null) 'mimeType': mimeType,
      },
    );
    return UploadSession.fromJson(parseData(response.data));
  }

  Future<void> uploadToPresignedUrl({
    required String presignedUrl,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(minutes: 10),
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    try {
      await dio.put<void>(
        presignedUrl,
        data: bytes,
        options: Options(
          headers: {
            if (mimeType != null) 'Content-Type': mimeType,
            'Content-Length': bytes.length,
          },
        ),
      );
    } finally {
      dio.close(force: true);
    }
  }

  Future<FileUploadCompleteResult> completeUploadSession({
    required String uploadId,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/uploads/$uploadId/complete',
    );
    return FileUploadCompleteResult.fromJson(parseData(response.data));
  }
}
