import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:omninest/core/errors/app_exception.dart';
import 'package:omninest/core/security/encrypted_file_vault.dart';
import 'package:omninest/core/security/offline_memory_cache.dart';
import 'package:omninest/features/reader/data/cached_book_handle.dart';
import 'package:omninest/features/reader/reader_debug_log.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 阅读器本地文件缓存管理
///
/// 管理已下载书籍文件的缓存，支持 Web/桌面/移动全平台。
/// - Web 平台：内存缓存（无文件系统）
/// - 本地平台：文件系统缓存 + 500MB LRU 淘汰
class LocalBookCache {
  LocalBookCache({
    required this.userId,
    required EncryptedFileVault vault,
    Future<Directory> Function(String userId)? cacheDirectoryResolver,
  }) : _vault = vault,
       _cacheDirectoryResolver = cacheDirectoryResolver;

  final String? userId;
  final EncryptedFileVault _vault;
  final Future<Directory> Function(String userId)? _cacheDirectoryResolver;

  static Future<void>? _legacyCleanup;
  static final Map<String, Future<void>> _sessionCleanupByDirectory = {};
  static final Random _secureRandom = Random.secure();

  /// 本地平台缓存大小上限（500MB）
  static const _maxCacheBytes = 500 * 1024 * 1024;

  /// Web 与 TXT 整包解析上限。
  static const maxInMemoryParseBytes = 32 * 1024 * 1024;

  /// 原生平台 TXT 会话级解码上限（整本解码一次并缓存，峰值内存约为
  /// 文件体积的 2-3 倍，桌面端可承受；Web 保持整包内存上限不变）。
  static const maxNativeParseBytes = 64 * 1024 * 1024;

  /// 确保文件已缓存，并返回会话级解析句柄。
  Future<CachedBookHandle> ensureCachedHandle(
    String itemId, {
    Future<Uint8List> Function()? webDownloader,
    Future<void> Function(String destinationPath)? nativeDownloader,
  }) async {
    final currentUserId = userId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return CachedBookHandle.memory(Uint8List(0));
    }
    if (kIsWeb) {
      final bytes = await ensureCachedBytes(
        itemId,
        webDownloader: webDownloader,
      );
      if (bytes.length > maxInMemoryParseBytes) {
        throw const FormatException('Web 阅读文件超过 32 MiB 解析上限');
      }
      return CachedBookHandle.memory(bytes);
    }

    final cacheFile = await _ensureNativeCacheFile(
      itemId,
      nativeDownloader: nativeDownloader,
    );
    if (cacheFile == null) {
      return CachedBookHandle.memory(Uint8List(0));
    }
    final sessionFile = File(
      '${cacheFile.path}.plain.session.${_createSessionToken()}',
    );
    return CachedBookHandle.file(
      openFile:
          () => _openSessionFile(
            itemId: itemId,
            cacheFile: cacheFile,
            sessionFile: sessionFile,
            nativeDownloader: nativeDownloader,
          ),
      closeFile: (_) => _deleteSessionFile(sessionFile),
    );
  }

  /// 确保文件已缓存并返回字节
  ///
  /// 优先从缓存读取，不存在则按平台调用对应下载器。
  /// 返回文件字节（可直接用于 EPUB 解析）。
  Future<Uint8List> ensureCachedBytes(
    String itemId, {
    Future<Uint8List> Function()? webDownloader,
    Future<void> Function(String destinationPath)? nativeDownloader,
  }) async {
    final currentUserId = userId;
    if (currentUserId == null || currentUserId.isEmpty) {
      return Uint8List(0);
    }
    // Web 平台：内存缓存
    if (kIsWeb) {
      final cached = OfflineMemoryCache.read(
        userId: currentUserId,
        cacheType: 'reader-book',
        businessId: itemId,
      );
      if (cached != null) {
        if (kDebugMode) {
          readerDebugLog('LocalBookCache: memory cache hit for $itemId');
        }
        return cached;
      }
      if (kDebugMode) {
        readerDebugLog('LocalBookCache: downloading $itemId (web)');
      }
      if (webDownloader == null) {
        return Uint8List(0);
      }
      final bytes = await _downloadWithTimeout(webDownloader, itemId);
      if (bytes.isNotEmpty) {
        OfflineMemoryCache.write(
          userId: currentUserId,
          cacheType: 'reader-book',
          businessId: itemId,
          bytes: bytes,
        );
      }
      return bytes;
    }

    // 本地平台：文件系统缓存
    final file = await _fileFor(itemId);
    if (await file.exists()) {
      try {
        final bytes = await _vault.decryptToBytes(
          source: file,
          context: _context(itemId),
          maxBytes: _maxCacheBytes,
        );
        await file.setLastAccessed(DateTime.now());
        if (kDebugMode) {
          readerDebugLog('LocalBookCache: encrypted cache hit for $itemId');
        }
        return bytes;
      } on FormatException {
        await file.delete();
      }
    }
    if (nativeDownloader == null) {
      return Uint8List(0);
    }
    if (kDebugMode) {
      readerDebugLog('LocalBookCache: downloading $itemId (native)');
    }
    await _downloadToFile(file, itemId, nativeDownloader);
    await _evictIfNeeded(protectedPath: file.path);
    return _vault.decryptToBytes(
      source: file,
      context: _context(itemId),
      maxBytes: _maxCacheBytes,
    );
  }

  Future<File?> _ensureNativeCacheFile(
    String itemId, {
    Future<void> Function(String destinationPath)? nativeDownloader,
  }) async {
    final file = await _fileFor(itemId);
    if (await file.exists()) {
      await file.setLastAccessed(DateTime.now());
      return file;
    }
    if (nativeDownloader == null) return null;
    await _downloadToFile(file, itemId, nativeDownloader);
    await _evictIfNeeded(protectedPath: file.path);
    return file;
  }

  Future<File> _openSessionFile({
    required String itemId,
    required File cacheFile,
    required File sessionFile,
    Future<void> Function(String destinationPath)? nativeDownloader,
  }) async {
    await _deleteSessionFile(sessionFile);
    try {
      await _vault.decryptToFile(
        source: cacheFile,
        destination: sessionFile,
        context: _context(itemId),
      );
    } on FormatException {
      await cacheFile.delete();
      if (nativeDownloader != null) {
        await _downloadToFile(cacheFile, itemId, nativeDownloader);
      } else {
        rethrow;
      }
      await _vault.decryptToFile(
        source: cacheFile,
        destination: sessionFile,
        context: _context(itemId),
      );
      await _evictIfNeeded(protectedPath: cacheFile.path);
    }
    await cacheFile.setLastAccessed(DateTime.now());
    return sessionFile;
  }

  /// 带超时的下载。失败必须抛出：返回空字节会让上层把「取不到」当成
  /// 「该书没有正文」，章节页只剩空白且没有重试入口。
  Future<Uint8List> _downloadWithTimeout(
    Future<Uint8List> Function() downloader,
    String itemId,
  ) async {
    try {
      final bytes = await downloader().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw const AppException(
            code: 'READER_BOOK_DOWNLOAD_TIMEOUT',
            message: '书籍内容下载超时',
          );
        },
      );
      if (kDebugMode) {
        readerDebugLog(
          'LocalBookCache: downloaded ${bytes.length} bytes for $itemId',
        );
      }
      return bytes;
    } on AppException {
      rethrow;
    } on FormatException {
      rethrow;
    } catch (e) {
      if (kDebugMode) {
        readerDebugLog('LocalBookCache: download failed for $itemId: $e');
      }
      throw AppException(
        code: 'READER_BOOK_DOWNLOAD_FAILED',
        message: '书籍内容下载失败',
        details: {'itemId': itemId, 'cause': e.toString()},
      );
    }
  }

  /// 将网络响应直接写入临时文件，完成后再原子替换缓存文件。
  ///
  /// 失败抛出 [AppException] 并携带原因，避免上层把「取不到」当成
  /// 「该书没有正文」。
  Future<void> _downloadToFile(
    File file,
    String itemId,
    Future<void> Function(String destinationPath) downloader,
  ) async {
    final partialFile = File('${file.path}.plain.part');
    try {
      await file.parent.create(recursive: true);
      await downloader(partialFile.path).timeout(const Duration(minutes: 15));
      if (!await partialFile.exists() || await partialFile.length() == 0) {
        throw const AppException(
          code: 'READER_BOOK_DOWNLOAD_FAILED',
          message: '书籍内容下载失败',
        );
      }
      await _vault.encryptFile(
        source: partialFile,
        destination: file,
        context: _context(itemId),
      );
      await partialFile.delete();
    } catch (error) {
      if (kDebugMode) {
        readerDebugLog('LocalBookCache: download failed for $itemId: $error');
      }
      if (await partialFile.exists()) {
        try {
          await partialFile.delete();
        } on Exception catch (deleteError) {
          if (kDebugMode) {
            readerDebugLog(
              'LocalBookCache: partial cleanup failed for $itemId: $deleteError',
            );
          }
        }
      }
      if (error is AppException) {
        rethrow;
      }
      throw AppException(
        code: 'READER_BOOK_DOWNLOAD_FAILED',
        message: '书籍内容下载失败',
        details: {'itemId': itemId, 'cause': error.toString()},
      );
    }
  }

  /// 检查指定条目是否已缓存
  Future<bool> isCached(String itemId) async {
    final currentUserId = userId;
    if (currentUserId == null || currentUserId.isEmpty) return false;
    if (kIsWeb) {
      return OfflineMemoryCache.contains(
        userId: currentUserId,
        cacheType: 'reader-book',
        businessId: itemId,
      );
    }
    final file = await _fileFor(itemId);
    return file.exists();
  }

  /// 删除指定条目的缓存
  Future<void> removeCache(String itemId) async {
    final currentUserId = userId;
    if (currentUserId == null || currentUserId.isEmpty) return;
    OfflineMemoryCache.remove(
      userId: currentUserId,
      cacheType: 'reader-book',
      businessId: itemId,
    );
    if (kIsWeb) return;
    final file = await _fileFor(itemId);
    if (await file.exists()) {
      await file.delete();
    }
    await _deletePartialFiles(file);
  }

  /// 清空全部缓存
  Future<void> clearAll() async {
    final currentUserId = userId;
    if (currentUserId != null && currentUserId.isNotEmpty) {
      OfflineMemoryCache.clearUser(currentUserId);
    }
    if (kIsWeb) return;
    if (userId == null || userId!.isEmpty) return;
    final dir = await _getCacheDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// 获取指定条目的缓存文件引用（仅本地平台）
  Future<File> _fileFor(String itemId) async {
    final dir = await _getCacheDir();
    return File(p.join(dir.path, '${_encodePathSegment(itemId)}.onf'));
  }

  /// 获取缓存目录（仅本地平台）
  Future<Directory> _getCacheDir() async {
    final currentUserId = userId;
    if (currentUserId == null || currentUserId.isEmpty) {
      throw const FileSystemException('当前用户未登录');
    }
    final resolver = _cacheDirectoryResolver;
    late final Directory directory;
    if (resolver != null) {
      directory = await resolver(currentUserId);
    } else {
      await (_legacyCleanup ??= _deleteLegacyPlaintextCache());
      final appDir = await getTemporaryDirectory();
      directory = Directory(
        p.join(
          appDir.path,
          'reader_cache_v2',
          _encodePathSegment(currentUserId),
        ),
      );
    }
    await directory.create(recursive: true);
    final cleanupKey = p.normalize(directory.absolute.path);
    await (_sessionCleanupByDirectory[cleanupKey] ??=
        _deleteAbandonedSessionFiles(directory));
    return directory;
  }

  Future<void> _deleteAbandonedSessionFiles(Directory directory) async {
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.contains('.plain.session')) continue;
      try {
        await entity.delete();
      } on FileSystemException catch (error) {
        if (kDebugMode) {
          readerDebugLog(
            'LocalBookCache: abandoned session cleanup failed: $error',
          );
        }
      }
    }
  }

  Future<void> _deleteSessionFilesForCache(File cacheFile) async {
    final prefix = '${p.basename(cacheFile.path)}.plain.session';
    await for (final entity in cacheFile.parent.list()) {
      if (entity is File && p.basename(entity.path).startsWith(prefix)) {
        await _deleteSessionFile(entity);
      }
    }
  }

  Future<void> _deleteLegacyPlaintextCache() async {
    final documents = await getApplicationDocumentsDirectory();
    final temporary = await getTemporaryDirectory();
    final legacyDirectories = <Directory>[
      Directory(p.join(documents.path, 'reader_cache')),
      Directory(p.join(temporary.path, 'reader_cache')),
    ];
    for (final legacy in legacyDirectories) {
      if (await legacy.exists()) {
        await legacy.delete(recursive: true);
      }
    }
  }

  OfflineFileContext _context(String itemId) {
    return OfflineFileContext(
      userId: userId!,
      cacheType: 'reader-book',
      businessId: itemId,
    );
  }

  String _encodePathSegment(String value) {
    return base64UrlEncode(utf8.encode(value)).replaceAll('=', '');
  }

  static String _createSessionToken() {
    final bytes = List<int>.generate(
      18,
      (_) => _secureRandom.nextInt(256),
      growable: false,
    );
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  Future<void> _deletePartialFiles(File cacheFile) async {
    final partialFile = File('${cacheFile.path}.plain.part');
    final metadataFile = File('${partialFile.path}.resume.json');
    if (await partialFile.exists()) {
      await partialFile.delete();
    }
    if (await metadataFile.exists()) {
      await metadataFile.delete();
    }
    await _deleteSessionFilesForCache(cacheFile);
  }

  Future<void> _deleteSessionFile(File sessionFile) async {
    final decryptingFile = File('${sessionFile.path}.decrypting');
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        if (await sessionFile.exists()) {
          await sessionFile.delete();
        }
        if (await decryptingFile.exists()) {
          await decryptingFile.delete();
        }
        return;
      } on FileSystemException {
        if (attempt == 3) {
          if (kDebugMode) {
            readerDebugLog(
              'LocalBookCache: session cleanup deferred for ${sessionFile.path}',
            );
          }
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  /// LRU 淘汰：缓存超限时删除最久未访问的文件
  Future<void> _evictIfNeeded({String? protectedPath}) async {
    final dir = await _getCacheDir();
    if (!await dir.exists()) return;

    final filePaths = <String>[];
    var totalSize = 0;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.onf')) {
        filePaths.add(entity.path);
        totalSize += await entity.length();
      }
    }

    if (totalSize <= _maxCacheBytes) return;

    // 排序与删除移入后台 isolate，避免大量同步 stat/删除阻塞 UI。
    final evictedPaths = await Isolate.run(() {
      final candidates =
          filePaths.map((path) => (path: path, file: File(path))).toList();
      candidates.sort((a, b) {
        final aTime = a.file.lastAccessedSync();
        final bTime = b.file.lastAccessedSync();
        return aTime.compareTo(bTime);
      });
      final toDelete = <String>[];
      var size = totalSize;
      for (final candidate in candidates) {
        // 留 20% 余量
        if (size <= _maxCacheBytes * 0.8) break;
        if (protectedPath != null && p.equals(candidate.path, protectedPath)) {
          continue;
        }
        final fileSize = candidate.file.lengthSync();
        candidate.file.deleteSync();
        size -= fileSize;
        toDelete.add(candidate.path);
      }
      return toDelete;
    });

    for (final path in evictedPaths) {
      if (kDebugMode) {
        readerDebugLog('LocalBookCache: evicted ${p.basename(path)}');
      }
    }
  }
}
