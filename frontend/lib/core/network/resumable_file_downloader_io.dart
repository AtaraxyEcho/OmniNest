import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/core/network/resumable_file_ticket.dart';

const _resumeMetadataSuffix = '.resume.json';

/// 使用签名地址和 HTTP Range 将文件续传到本地路径。
Future<void> downloadResumableFileToPath({
  required Dio dio,
  required ResumableFileTicket ticket,
  required String destinationPath,
}) async {
  _validateTicket(ticket);
  final destination = File(destinationPath);
  final metadataFile = File('$destinationPath$_resumeMetadataSuffix');
  await destination.parent.create(recursive: true);

  var existingBytes = await _existingLength(destination);
  var metadata = await _readMetadata(metadataFile);
  if (existingBytes == ticket.sizeBytes &&
      await _matchesDigest(destination, ticket.sha256)) {
    await _deleteIfExists(metadataFile);
    return;
  }
  if (existingBytes >= ticket.sizeBytes ||
      (existingBytes > 0 &&
          (metadata == null || !metadata.matchesTicket(ticket)))) {
    await _resetPartial(destination, metadataFile);
    existingBytes = 0;
    metadata = null;
  }

  var restarted = false;
  while (true) {
    final response = await _request(dio, ticket, existingBytes);
    final responseBody = response.data;
    if (responseBody == null) {
      throw AppException(
        code: ticket.errorCode('EMPTY_RESPONSE'),
        message: '${ticket.fileLabel}下载响应为空',
      );
    }
    final etag = _normalizeHeader(response.headers.value('etag'));
    final resumeDecision = _resumeDecision(
      response: response,
      existingBytes: existingBytes,
      expectedSize: ticket.sizeBytes,
      previousEtag: metadata?.etag,
    );
    if (resumeDecision == _ResumeDecision.restart) {
      await responseBody.stream.drain<void>();
      await _resetPartial(destination, metadataFile);
      if (restarted) {
        throw AppException(
          code: ticket.errorCode('RANGE_INVALID'),
          message: '${ticket.fileLabel}续传响应不符合 Range 约束',
        );
      }
      existingBytes = 0;
      metadata = null;
      restarted = true;
      continue;
    }
    if (resumeDecision == _ResumeDecision.ticketChanged) {
      await responseBody.stream.drain<void>();
      await _resetPartial(destination, metadataFile);
      throw AppException(
        code: ticket.errorCode('TICKET_CHANGED'),
        message: '${ticket.fileLabel}版本已变化，请重新下载',
      );
    }

    final append = existingBytes > 0 && response.statusCode == 206;
    if (!append) {
      existingBytes = 0;
    }
    metadata = _ResumeMetadata(
      sizeBytes: ticket.sizeBytes,
      sha256: _normalizeDigest(ticket.sha256),
      etag: etag,
    );
    await _writeMetadata(metadataFile, metadata);
    await _writeResponse(
      destination: destination,
      responseBody: responseBody,
      append: append,
      maxBytes: ticket.sizeBytes > 0 ? ticket.sizeBytes : null,
    );
    break;
  }

  final actualSize = await _existingLength(destination);
  if (actualSize < ticket.sizeBytes) {
    throw AppException(
      code: ticket.errorCode('DOWNLOAD_INCOMPLETE'),
      message: '${ticket.fileLabel}下载未完成',
      details: {'expectedBytes': ticket.sizeBytes, 'actualBytes': actualSize},
    );
  }
  if (actualSize > ticket.sizeBytes) {
    await _resetPartial(destination, metadataFile);
    throw AppException(
      code: ticket.errorCode('SIZE_MISMATCH'),
      message: '${ticket.fileLabel}大小校验失败',
    );
  }
  if (!await _matchesDigest(destination, ticket.sha256)) {
    await _resetPartial(destination, metadataFile);
    throw AppException(
      code: ticket.errorCode('DIGEST_MISMATCH'),
      message: '${ticket.fileLabel}完整性校验失败',
    );
  }
  await _deleteIfExists(metadataFile);
}

void _validateTicket(ResumableFileTicket ticket) {
  if (ticket.downloadUrl.isEmpty || ticket.sizeBytes <= 0) {
    throw AppException(
      code: ticket.errorCode('TICKET_INVALID'),
      message: '${ticket.fileLabel}下载票据无效',
    );
  }
}

Future<Response<ResponseBody>> _request(
  Dio dio,
  ResumableFileTicket ticket,
  int existingBytes,
) {
  return dio.get<ResponseBody>(
    ticket.downloadUrl,
    options: Options(
      responseType: ResponseType.stream,
      receiveTimeout: const Duration(minutes: 15),
      headers: {if (existingBytes > 0) 'Range': 'bytes=$existingBytes-'},
      extra: const {ApiClient.skipAuthorizationKey: true},
      validateStatus: (status) => status == 200 || status == 206,
    ),
  );
}

_ResumeDecision _resumeDecision({
  required Response<ResponseBody> response,
  required int existingBytes,
  required int expectedSize,
  required String? previousEtag,
}) {
  if (existingBytes == 0 || response.statusCode == 200) {
    return _ResumeDecision.continueDownload;
  }
  final contentRange = response.headers.value('content-range');
  final match =
      contentRange == null
          ? null
          : RegExp(r'^bytes (\d+)-(\d+)/(\d+|\*)$').firstMatch(contentRange);
  if (response.statusCode != 206 || match == null) {
    return _ResumeDecision.restart;
  }
  final rangeStart = int.tryParse(match.group(1) ?? '');
  final totalSize = int.tryParse(match.group(3) ?? '');
  if (rangeStart != existingBytes) {
    return _ResumeDecision.restart;
  }
  if (totalSize != null && totalSize != expectedSize) {
    return _ResumeDecision.ticketChanged;
  }
  final currentEtag = _normalizeHeader(response.headers.value('etag'));
  if (previousEtag != null &&
      currentEtag != null &&
      previousEtag != currentEtag) {
    return _ResumeDecision.restart;
  }
  return _ResumeDecision.continueDownload;
}

Future<void> _writeResponse({
  required File destination,
  required ResponseBody responseBody,
  required bool append,
  int? maxBytes,
}) async {
  RandomAccessFile? output;
  try {
    output = await destination.open(
      mode: append ? FileMode.append : FileMode.write,
    );
    var written =
        append && await destination.exists() ? await destination.length() : 0;
    await for (final chunk in responseBody.stream) {
      written += chunk.length;
      // 边写边校验上限：只在流结束后校验会让异常超长响应先把磁盘写满。
      if (maxBytes != null && written > maxBytes) {
        throw AppException(
          code: 'DOWNLOAD_SIZE_EXCEEDED',
          message: '下载内容超出声明的文件大小',
        );
      }
      await output.writeFrom(chunk);
    }
    await output.flush();
  } finally {
    await output?.close();
  }
}

Future<bool> _matchesDigest(File file, String? expectedDigest) async {
  final normalizedExpected = _normalizeDigest(expectedDigest);
  if (normalizedExpected == null) {
    return true;
  }
  final path = file.path;
  final actualDigest = await Isolate.run(() async {
    final digest = await sha256.bind(File(path).openRead()).first;
    return digest.toString().toLowerCase();
  });
  return actualDigest == normalizedExpected;
}

Future<_ResumeMetadata?> _readMetadata(File file) async {
  if (!await file.exists()) {
    return null;
  }
  try {
    final value = jsonDecode(await file.readAsString());
    if (value is! Map<String, dynamic>) {
      return null;
    }
    return _ResumeMetadata.fromJson(value);
  } on FormatException {
    return null;
  }
}

Future<void> _writeMetadata(File file, _ResumeMetadata metadata) async {
  final temporary = File('${file.path}.writing');
  await temporary.writeAsString(jsonEncode(metadata.toJson()), flush: true);
  try {
    // 直接覆盖重命名：先删后改名之间存在进程中断就丢元数据的窗口。
    await temporary.rename(file.path);
  } on FileSystemException {
    // Windows 上目标存在时 rename 会失败，退化为删除后重试。
    await _deleteIfExists(file);
    await temporary.rename(file.path);
  }
}

Future<int> _existingLength(File file) async {
  return await file.exists() ? file.length() : 0;
}

Future<void> _resetPartial(File destination, File metadataFile) async {
  await _deleteIfExists(destination);
  await _deleteIfExists(metadataFile);
}

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) {
    await file.delete();
  }
}

String? _normalizeHeader(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

String? _normalizeDigest(String? value) {
  final normalized = value?.trim().toLowerCase();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

enum _ResumeDecision { continueDownload, restart, ticketChanged }

class _ResumeMetadata {
  const _ResumeMetadata({
    required this.sizeBytes,
    required this.sha256,
    required this.etag,
  });

  final int sizeBytes;
  final String? sha256;
  final String? etag;

  factory _ResumeMetadata.fromJson(Map<String, dynamic> json) {
    return _ResumeMetadata(
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      sha256: _normalizeDigest(json['sha256']?.toString()),
      etag: _normalizeHeader(json['etag']?.toString()),
    );
  }

  bool matchesTicket(ResumableFileTicket ticket) {
    return sizeBytes == ticket.sizeBytes &&
        sha256 == _normalizeDigest(ticket.sha256);
  }

  Map<String, Object?> toJson() {
    return {'sizeBytes': sizeBytes, 'sha256': sha256, 'etag': etag};
  }
}
