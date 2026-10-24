import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:omninest/core/config/file_size_thresholds.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/errors/envelope_guard.dart';
import 'package:omninest/core/errors/error_codes.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/core/network/capability_gate_interceptor.dart';
import 'package:omninest/features/files/data/file_api_response_parser.dart';
import 'package:omninest/features/files/domain/file_manager_models.dart';
import 'package:omninest/features/files/application/file_download_url_provider.dart';
import 'package:omninest/features/files/domain/file_node.dart';
import 'package:omninest/features/files/domain/file_upload_complete_result.dart';
import 'package:omninest/features/files/domain/file_upload_session.dart';
import 'package:omninest/features/files/domain/public_share.dart';
import 'package:omninest/features/tasks/domain/task_record.dart';

part 'file_api_browse.dart';
part 'file_api_shares.dart';
part 'file_api_upload.dart';
part 'file_api_external.dart';

abstract class FileApiBase {
  FileApiBase(this.apiClient, {Dio? uploadDio})
    : _uploadDio = uploadDio ?? Dio();

  static const String _binaryContentType = 'application/octet-stream';
  static const int _textPreviewMaxBytes =
      FileSizeThresholds.textPreviewMaxBytes;
  static const Duration _externalStorageTimeout = Duration(seconds: 15);
  static const FileApiResponseParser _responseParser = FileApiResponseParser();

  final ApiClient apiClient;
  final Dio _uploadDio;
  final Map<String, String> _shareSessionTokens = <String, String>{};

  void close() => _uploadDio.close(force: true);

  FileNodePage parseFilePageResponse(Map<String, dynamic>? body) {
    return _responseParser.parseFilePageResponse(body);
  }

  FileNode parseFileNodeResponse(Map<String, dynamic>? body) {
    return _responseParser.parseFileNodeResponse(body);
  }

  List<FileNode> parseBatchFileNodeResponse(Map<String, dynamic>? body) {
    return _responseParser.parseBatchFileNodeResponse(body);
  }

  FileUploadSession parseUploadSessionResponse(Map<String, dynamic>? body) {
    return _responseParser.parseUploadSessionResponse(body);
  }

  FileUploadPartsInfo parseUploadPartsResponse(Map<String, dynamic>? body) {
    return _responseParser.parseUploadPartsResponse(body);
  }

  FileStorageStats parseStorageStatsResponse(Map<String, dynamic>? body) {
    return _responseParser.parseStorageStatsResponse(body);
  }

  FileUploadPolicy parseUploadPolicyResponse(Map<String, dynamic>? body) {
    return _responseParser.parseUploadPolicyResponse(body);
  }

  List<FileShareLink> parseShareLinkPageResponse(Map<String, dynamic>? body) {
    return _responseParser.parseShareLinkPageResponse(body);
  }

  FileShareLink parseShareLinkResponse(Map<String, dynamic>? body) {
    return _responseParser.parseShareLinkResponse(body);
  }

  List<SharedFileItem> parseSharedItemPageResponse(Map<String, dynamic>? body) {
    return _responseParser.parseSharedItemPageResponse(body);
  }

  List<FileUploadQueueItem> parseUploadQueuePageResponse(
    Map<String, dynamic>? body,
  ) {
    return _responseParser.parseUploadQueuePageResponse(body);
  }

  List<ExternalStorageAccount> parseExternalStoragePageResponse(
    Map<String, dynamic>? body,
  ) {
    return _responseParser.parseExternalStoragePageResponse(body);
  }

  ExternalStorageAccount parseExternalStorageResponse(
    Map<String, dynamic>? body,
  ) {
    return _responseParser.parseExternalStorageResponse(body);
  }

  void parseEmptyResponse(Map<String, dynamic>? body) {
    _responseParser.parseEmptyResponse(body);
  }

  Map<String, dynamic> parseData(Map<String, dynamic>? body) {
    return _responseParser.parseData(body);
  }

  Map<String, dynamic> parseEnvelope(Map<String, dynamic>? body) {
    return _responseParser.parseEnvelope(body);
  }
}

class FileApi extends FileApiBase
    with FileApiBrowse, FileApiShares, FileApiUpload, FileApiExternal {
  FileApi(super.apiClient, {super.uploadDio});
}
