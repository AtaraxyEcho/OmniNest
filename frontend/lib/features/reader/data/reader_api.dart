import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/reader/data/reader_file_downloader.dart';
import 'package:omninest/features/reader/domain/reader_models.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

/// 文本书籍解析任务状态，对应后端 TextManifestDto.parseTask。
class TextParseTask {
  const TextParseTask({
    required this.id,
    required this.status,
    required this.progress,
    this.errorMessage,
    this.updatedAt,
  });

  factory TextParseTask.fromJson(Map<String, dynamic> json) {
    return TextParseTask(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      progress: ((json['progress'] as num?)?.toInt() ?? 0).clamp(0, 100),
      errorMessage: json['errorMessage']?.toString(),
      updatedAt: json['updatedAt']?.toString(),
    );
  }

  final String id;
  final String status;
  final int progress;
  final String? errorMessage;
  final String? updatedAt;

  bool get isParsing =>
      status == 'QUEUED' || status == 'RUNNING' || status == 'RETRY_WAIT';
}

/// 阅读器模块 API 客户端
class ReaderApi {
  const ReaderApi(this.apiClient);

  static const _coverMaxBytes = 12 * 1024 * 1024;
  static const _webBookMaxBytes = 32 * 1024 * 1024;
  static const _webPdfMaxBytes = 128 * 1024 * 1024;

  final ApiClient apiClient;

  // ─── Dashboard ───────────────────────────────────────────────

  /// 获取阅读器仪表盘数据
  Future<ReaderDashboard> dashboard() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/reader/dashboard',
    );
    return ReaderDashboard.fromJson(parseData(response.data));
  }

  // ─── Items ───────────────────────────────────────────────────

  /// 获取阅读条目列表
  ///
  /// [itemType] 可选过滤类型（EPUB、TXT、CBZ、ZIP）
  /// [query] 可选搜索关键词
  Future<List<ReaderItem>> items({String? itemType, String? query}) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/reader/items',
      queryParameters: {
        if (itemType != null) 'itemType': itemType,
        if (query != null) 'query': query,
      },
    );
    return _parseList(response.data, ReaderItem.fromJson, '阅读条目列表格式不正确');
  }

  /// 获取阅读条目详情（含进度）
  Future<ReaderItemDetail> detail(String itemId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/reader/items/$itemId',
    );
    return ReaderItemDetail.fromJson(parseData(response.data));
  }

  /// 获取服务端持久化的 EPUB/TXT 章节清单。
  Future<
    ({
      ParsedBook book,
      String importStatus,
      String? errorCode,
      String? errorMessage,
      TextParseTask? parseTask,
    })
  >
  getTextManifest(String itemId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/reader/items/$itemId/text/manifest',
    );
    final data = parseData(response.data);
    final chaptersData = data['chapters'];
    final chapters = <ParsedChapter>[];
    if (chaptersData is List) {
      for (final value in chaptersData) {
        if (value is! Map) continue;
        final chapter = Map<String, dynamic>.from(value);
        final index = (chapter['index'] as num?)?.toInt() ?? chapters.length;
        chapters.add(
          ParsedChapter(
            number: index + 1,
            title: chapter['title']?.toString() ?? '第 ${index + 1} 章',
            xhtmlContent: '',
            charCount: (chapter['charCount'] as num?)?.toInt() ?? 0,
            contentPath: chapter['contentPath']?.toString(),
            level: (chapter['level'] as num?)?.toInt() ?? 0,
            sourceStartOffset: (chapter['sourceStartOffset'] as num?)?.toInt(),
            sourceEndOffset: (chapter['sourceEndOffset'] as num?)?.toInt(),
          ),
        );
      }
    }
    final parseTaskData = data['parseTask'];
    return (
      book: ParsedBook(
        title: data['title']?.toString(),
        author: data['author']?.toString(),
        description: data['description']?.toString(),
        publisher: data['publisher']?.toString(),
        language: data['language']?.toString(),
        chapters: chapters,
      ),
      importStatus: data['importStatus']?.toString() ?? 'PARSING',
      errorCode: data['errorCode']?.toString(),
      errorMessage: data['errorMessage']?.toString(),
      parseTask:
          parseTaskData is Map
              ? TextParseTask.fromJson(Map<String, dynamic>.from(parseTaskData))
              : null,
    );
  }

  /// 删除阅读条目
  Future<TaskSubmission> deleteItem(
    String itemId, {
    bool cascade = false,
  }) async {
    final response = await apiClient.dio.delete<Map<String, dynamic>>(
      '/reader/items/$itemId',
      queryParameters: {'cascade': cascade},
    );
    return TaskSubmission.fromJson(parseData(response.data));
  }

  /// 取消仍在排队或解析中的阅读导入任务。
  Future<void> cancelImport(String itemId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/reader/items/$itemId/import/cancel',
    );
    parseEnvelope(response.data);
  }

  // ─── File Download ───────────────────────────────────────────

  /// 获取原始文件临时下载票据。
  Future<ReaderFileTicket> getFileTicket(String itemId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/reader/items/$itemId/file-ticket',
    );
    return ReaderFileTicket.fromJson(parseData(response.data));
  }

  /// Web 兼容路径：从签名地址读取原始文件字节。
  ///
  /// PDF 上限 128MiB；EPUB/TXT 维持 32MiB。
  Future<Uint8List> downloadFileBytes(String itemId, {String? itemType}) async {
    final ticket = await getFileTicket(itemId);
    if (ticket.downloadUrl.isEmpty || ticket.sizeBytes <= 0) {
      throw const AppException(
        code: 'READER_FILE_TICKET_INVALID',
        message: '阅读文件下载票据无效',
      );
    }
    final isPdf = itemType?.toUpperCase() == 'PDF';
    final maxBytes = isPdf ? _webPdfMaxBytes : _webBookMaxBytes;
    if (ticket.sizeBytes > maxBytes) {
      throw AppException(
        code: isPdf ? 'READER_WEB_PDF_TOO_LARGE' : 'READER_WEB_FILE_TOO_LARGE',
        message: isPdf ? 'errorWebPdfTooLarge' : 'errorWebBookTooLarge',
      );
    }
    final response = await apiClient.dio.get<List<int>>(
      ticket.downloadUrl,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(minutes: 5),
        extra: const {ApiClient.skipAuthorizationKey: true},
        validateStatus:
            (status) => status != null && status >= 200 && status < 300,
      ),
    );
    final bytes = _asUint8List(response.data);
    if (bytes.length != ticket.sizeBytes) {
      throw AppException(
        code: 'READER_FILE_SIZE_MISMATCH',
        message: '阅读文件大小校验失败',
        details: {
          'expectedBytes': ticket.sizeBytes,
          'actualBytes': bytes.length,
        },
      );
    }
    final expectedDigest = ticket.sha256?.trim().toLowerCase();
    if (expectedDigest != null &&
        expectedDigest.isNotEmpty &&
        sha256.convert(bytes).toString().toLowerCase() != expectedDigest) {
      throw const AppException(
        code: 'READER_FILE_DIGEST_MISMATCH',
        message: '阅读文件完整性校验失败',
      );
    }
    return bytes;
  }

  /// 原生平台路径：从签名地址直接写入临时文件。
  Future<void> downloadFileToPath(String itemId, String destinationPath) async {
    final ticket = await getFileTicket(itemId);
    await downloadReaderFileToPath(
      dio: apiClient.dio,
      ticket: ticket,
      destinationPath: destinationPath,
    );
  }

  /// 获取漫画页面图片字节。
  Future<Uint8List> getPageImage(String pageId) async {
    final response = await apiClient.dio.get<List<int>>(
      '/reader/pages/$pageId/image',
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = _asUint8List(response.data);
    if (bytes.isEmpty) {
      throw const AppException(
        message: '漫画图片为空',
        code: 'READER_COMIC_IMAGE_EMPTY',
      );
    }
    return bytes;
  }

  /// 获取有界封面图片字节。
  Future<Uint8List?> getCoverImage(String itemId) async {
    final response = await apiClient.dio.get<ResponseBody>(
      '/reader/items/$itemId/cover',
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Range': 'bytes=0-${_coverMaxBytes - 1}'},
        validateStatus: (status) => status == 200 || status == 206,
      ),
    );
    final body = response.data;
    if (body == null) {
      return null;
    }

    final bytes = BytesBuilder(copy: false);
    var remaining = _coverMaxBytes;
    await for (final chunk in body.stream) {
      if (remaining <= 0) {
        break;
      }
      if (chunk.length <= remaining) {
        bytes.add(chunk);
        remaining -= chunk.length;
      } else {
        bytes.add(chunk.sublist(0, remaining));
        remaining = 0;
      }
    }
    final result = bytes.takeBytes();
    return result.isEmpty ? null : result;
  }

  // ─── Progress ────────────────────────────────────────────────

  /// 更新阅读进度
  ///
  /// progressPercent 为全书进度（0-1），仅用于显示。
  /// 恢复定位使用 chapterId + charOffset（章节内字符偏移）。
  /// 漫画模式使用 pageId / pageIndex / pageFingerprint 精确定位。
  Future<void> updateProgress({
    required String itemId,
    int charOffset = 0,
    required double progressPercent,
    String readingMode = 'scroll',
    String? chapterId,
    String? pageId,
    int? pageIndex,
    String? pageFingerprint,
    String? sourceId,
    int? sourcePageIndex,
    String? catalogKey,
    int? manifestVersion,
    double? intraPageOffset,
  }) async {
    await apiClient.dio.put<Map<String, dynamic>>(
      '/reader/items/$itemId/progress',
      data: {
        'charOffset': charOffset,
        'progressPercent': progressPercent.clamp(0.0, 1.0),
        'readingMode': readingMode,
        if (chapterId != null) 'chapterId': chapterId,
        if (pageId != null) 'pageId': pageId,
        if (pageIndex != null) 'pageIndex': pageIndex,
        if (pageFingerprint != null) 'pageFingerprint': pageFingerprint,
        if (sourceId != null) 'sourceId': sourceId,
        if (sourcePageIndex != null) 'sourcePageIndex': sourcePageIndex,
        if (catalogKey != null) 'catalogKey': catalogKey,
        if (manifestVersion != null) 'manifestVersion': manifestVersion,
        if (intraPageOffset != null) 'intraPageOffset': intraPageOffset,
      },
    );
  }

  // ─── Bookmarks ───────────────────────────────────────────────

  /// 获取条目的书签列表
  Future<List<ReaderBookmark>> bookmarks(String itemId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/reader/items/$itemId/bookmarks',
    );
    return _parseList(response.data, ReaderBookmark.fromJson, '书签列表格式不正确');
  }

  /// 创建书签
  Future<ReaderBookmark> createBookmark({
    required String itemId,
    required int charOffset,
    required double progressPercent,
    String? note,
    String? clientOperationId,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/reader/items/$itemId/bookmarks',
      data: {
        'charOffset': charOffset,
        'progressPercent': progressPercent.clamp(0.0, 1.0),
        if (note != null) 'note': note,
        if (clientOperationId != null) 'clientOperationId': clientOperationId,
      },
    );
    return ReaderBookmark.fromJson(parseData(response.data));
  }

  /// 删除书签
  Future<void> deleteBookmark(String bookmarkId) async {
    await apiClient.dio.delete<Map<String, dynamic>>(
      '/reader/bookmarks/$bookmarkId',
    );
  }

  // ─── Annotations ─────────────────────────────────────────────

  /// 获取条目的标注列表
  Future<List<ReaderAnnotation>> annotations(String itemId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/reader/items/$itemId/annotations',
    );
    return _parseList(response.data, ReaderAnnotation.fromJson, '标注列表格式不正确');
  }

  /// 创建标注
  Future<ReaderAnnotation> createAnnotation({
    required String itemId,
    String? chapterId,
    required int startOffset,
    required int endOffset,
    String? highlightText,
    String? note,
    String? color,
    String? clientOperationId,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/reader/items/$itemId/annotations',
      data: {
        if (chapterId != null) 'chapterId': chapterId,
        'startOffset': startOffset,
        'endOffset': endOffset,
        if (highlightText != null) 'highlightText': highlightText,
        if (note != null) 'note': note,
        if (color != null) 'color': color,
        if (clientOperationId != null) 'clientOperationId': clientOperationId,
      },
    );
    return ReaderAnnotation.fromJson(parseData(response.data));
  }

  /// 更新标注
  Future<ReaderAnnotation> updateAnnotation(
    String annotationId, {
    String? note,
    String? color,
  }) async {
    final response = await apiClient.dio.put<Map<String, dynamic>>(
      '/reader/annotations/$annotationId',
      data: {if (note != null) 'note': note, if (color != null) 'color': color},
    );
    return ReaderAnnotation.fromJson(parseData(response.data));
  }

  /// 删除标注
  Future<void> deleteAnnotation(String annotationId) async {
    await apiClient.dio.delete<Map<String, dynamic>>(
      '/reader/annotations/$annotationId',
    );
  }

  // ─── Notes ───────────────────────────────────────────────────

  /// 获取条目的笔记列表
  Future<List<ReaderNote>> notes(String itemId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/reader/items/$itemId/notes',
    );
    return _parseList(response.data, ReaderNote.fromJson, '笔记列表格式不正确');
  }

  /// 创建笔记
  Future<ReaderNote> createNote({
    required String itemId,
    int? charOffset,
    String? title,
    required String content,
    String? clientOperationId,
  }) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/reader/items/$itemId/notes',
      data: {
        if (charOffset != null) 'charOffset': charOffset,
        if (title != null) 'title': title,
        'content': content,
        if (clientOperationId != null) 'clientOperationId': clientOperationId,
      },
    );
    return ReaderNote.fromJson(parseData(response.data));
  }

  /// 更新笔记
  Future<ReaderNote> updateNote(
    String noteId, {
    String? title,
    required String content,
  }) async {
    final response = await apiClient.dio.put<Map<String, dynamic>>(
      '/reader/notes/$noteId',
      data: {if (title != null) 'title': title, 'content': content},
    );
    return ReaderNote.fromJson(parseData(response.data));
  }

  /// 删除笔记
  Future<void> deleteNote(String noteId) async {
    await apiClient.dio.delete<Map<String, dynamic>>('/reader/notes/$noteId');
  }

  // ─── Bookshelf ───────────────────────────────────────────────

  /// 切换条目的书架状态
  Future<void> toggleBookshelf(String itemId) async {
    await apiClient.dio.post<Map<String, dynamic>>(
      '/reader/items/$itemId/bookshelf',
    );
  }

  // ─── Sessions ────────────────────────────────────────────────

  /// 记录阅读会话
  Future<void> recordSession({
    required String clientSessionId,
    required String itemId,
    required String startedAt,
    required String endedAt,
    required int durationSeconds,
  }) async {
    await apiClient.dio.post<Map<String, dynamic>>(
      '/reader/items/$itemId/sessions',
      data: {
        'clientSessionId': clientSessionId,
        'startedAt': startedAt,
        'endedAt': endedAt,
        'durationSeconds': durationSeconds,
      },
    );
  }

  // ─── Comics ──────────────────────────────────────────────────

  /// 重试失败的漫画来源（异步，任务入队后立即返回）。
  Future<bool> retryComicSource(String itemId, String sourceId) async {
    try {
      await apiClient.dio.post<Map<String, dynamic>>(
        '/reader/items/$itemId/comic/sources/$sourceId/retry',
      );
      return true;
    } on Exception {
      return false;
    }
  }

  /// 删除漫画来源及其页面。
  Future<void> deleteComicSource(String itemId, String sourceId) async {
    await apiClient.dio.delete<Map<String, dynamic>>(
      '/reader/items/$itemId/comic/sources/$sourceId',
    );
  }

  /// 请求生成漫画清单。
  ///
  /// 后端会创建或唤醒解析任务；返回值是当前已持久化的清单快照。
  Future<ComicManifest> generateComicManifest(String itemId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/reader/items/$itemId/comic/manifest',
    );
    final data = parseData(response.data);
    if (data.isEmpty) {
      throw const AppException(
        message: '漫画清单为空',
        code: 'READER_COMIC_MANIFEST_EMPTY',
      );
    }
    return _comicManifestFromData(itemId, data);
  }

  /// 获取漫画清单（来源 + 目录 + 页面）。
  ///
  /// 从后端读取已持久化的清单。漫画上传后由后端异步解析，
  /// 前端阅读链路不主动同步生成清单。
  Future<ComicManifest> getComicManifest(String itemId) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/reader/items/$itemId/comic/manifest',
    );
    final data = parseData(response.data);
    if (data.isEmpty) {
      throw const AppException(
        message: '漫画清单为空',
        code: 'READER_COMIC_MANIFEST_EMPTY',
      );
    }
    return _comicManifestFromData(itemId, data);
  }

  ComicManifest _comicManifestFromData(
    String itemId,
    Map<String, dynamic> data,
  ) {
    return ComicManifest.fromJson({
      'itemId': data['itemId'] ?? itemId,
      'sources': data['sources'] ?? [],
      'catalog': data['catalog'] ?? [],
      'pages': data['pages'] ?? [],
      'manifestVersion': data['manifestVersion'] ?? 0,
      'importStatus': data['importStatus'] ?? 'READY',
      'readingDirection': data['readingDirection'],
      'parseTask': data['parseTask'],
    });
  }

  /// 重新解析阅读条目。
  ///
  /// 文本条目由前端清理本地解析缓存；漫画条目由后端异步重建清单。
  Future<ReaderItem> reparseItem(String itemId) async {
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/reader/items/$itemId/reparse',
    );
    return ReaderItem.fromJson(parseData(response.data));
  }

  // ─── Stats ───────────────────────────────────────────────────

  /// 获取阅读统计
  Future<ReaderReadingStats> getStats() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/reader/stats',
    );
    return ReaderReadingStats.fromJson(parseData(response.data));
  }

  /// 阅读统计概览（统计页）：每日分钟数、完成/在读计数与在读列表。
  Future<ReaderStatsOverview> getStatsOverview({int days = 14}) async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/reader/stats/overview',
      queryParameters: {'days': days},
    );
    return ReaderStatsOverview.fromJson(parseData(response.data));
  }

  /// 更新条目元数据（用户级，仅限自己的条目）
  Future<void> updateItemMetadata({
    required String itemId,
    required Map<String, dynamic> fields,
  }) async {
    await apiClient.dio.put<Map<String, dynamic>>(
      '/reader/items/$itemId/metadata',
      data: fields,
    );
  }

  /// 导入文件到阅读器
  Future<ReaderItem> importFile({
    required String fileNodeId,
    bool force = false,
    String? contentKindOverride,
  }) async {
    final data = <String, dynamic>{'fileNodeId': fileNodeId, 'force': force};
    if (contentKindOverride != null && contentKindOverride.isNotEmpty) {
      data['contentKindOverride'] = contentKindOverride;
    }
    final response = await apiClient.dio.post<Map<String, dynamic>>(
      '/reader/import',
      data: data,
    );
    return ReaderItem.fromJson(parseData(response.data));
  }

  /// 获取导入候选文件列表（个人空间 + 共享空间）
  Future<List<ReaderImportCandidate>> importCandidates() async {
    final response = await apiClient.dio.get<Map<String, dynamic>>(
      '/reader/import/candidates',
    );
    return parseList(
      response.data,
    ).map(ReaderImportCandidate.fromJson).toList(growable: false);
  }

  /// 从文件节点设置封面
  Future<void> setCoverFromFile({
    required String itemId,
    required String fileNodeId,
  }) async {
    await apiClient.dio.post<Map<String, dynamic>>(
      '/reader/items/$itemId/cover/file',
      data: {'fileNodeId': fileNodeId},
    );
  }

  /// 上传封面图片
  Future<void> uploadCover({
    required String itemId,
    required List<int> imageBytes,
    required String fileName,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(imageBytes, filename: fileName),
    });
    await apiClient.dio.post<Map<String, dynamic>>(
      '/reader/items/$itemId/cover',
      data: formData,
    );
  }

  Uint8List _asUint8List(List<int>? bytes) {
    if (bytes == null || bytes.isEmpty) {
      return Uint8List(0);
    }
    return bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  }

  // ─── Envelope Parsing Helpers ────────────────────────────────

  /// 从响应信封中提取 data 对象
  Map<String, dynamic> parseData(Map<String, dynamic>? body) {
    final envelope = parseEnvelope(body);
    final data = envelope['data'];
    if (data is! Map<String, dynamic>) {
      throw const AppException(code: 'INVALID_RESPONSE', message: '阅读器响应格式不正确');
    }
    return data;
  }

  /// 从响应信封中提取 data 数组
  List<Map<String, dynamic>> parseList(Map<String, dynamic>? body) {
    final envelope = parseEnvelope(body);
    final data = envelope['data'];
    if (data is! List) {
      throw const AppException(
        code: 'INVALID_RESPONSE',
        message: '阅读器列表响应格式不正确',
      );
    }
    return data
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  /// 解析响应信封，校验 code 字段
  Map<String, dynamic> parseEnvelope(Map<String, dynamic>? body) {
    if (body == null) {
      throw const AppException(code: 'EMPTY_RESPONSE', message: '服务端没有返回阅读器结果');
    }
    final code = body['code'];
    if (code != 200) {
      throw AppException(
        code: code?.toString() ?? 'READER_ERROR',
        message: body['message']?.toString() ?? '阅读器操作失败',
      );
    }
    return body;
  }

  /// 将信封 data 数组映射为强类型列表
  List<T> _parseList<T>(
    Map<String, dynamic>? body,
    T Function(Map<String, dynamic>) mapper,
    String errorMessage,
  ) {
    final data = parseEnvelope(body)['data'];
    if (data is! List) {
      throw AppException(code: 'INVALID_RESPONSE', message: errorMessage);
    }
    return data
        .whereType<Map>()
        .map((item) => mapper(Map<String, dynamic>.from(item)))
        .toList();
  }
}
