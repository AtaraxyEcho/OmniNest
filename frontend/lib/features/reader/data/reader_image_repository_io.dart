import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:omninest/core/security/encrypted_file_vault.dart';
import 'package:omninest/core/security/offline_key_store.dart';
import 'package:omninest/core/storage/local_database.dart';
import 'package:omninest/features/reader/data/reader_image_repository_base.dart';
import 'package:omninest/core/config/file_size_thresholds.dart';

/// 创建原生平台阅读图片缓存仓库。
ReaderImageRepository createReaderImageRepository({
  required LocalDatabase database,
  required String userId,
}) {
  return IoReaderImageRepository(
    database: database,
    userId: userId,
    vault: EncryptedFileVault(keyStore: createOfflineKeyStore()),
    rootDirectory: getTemporaryDirectory,
  );
}

/// 使用加密文件和 SQLite 索引保存原生平台阅读图片。
class IoReaderImageRepository implements ReaderImageRepository {
  IoReaderImageRepository({
    required LocalDatabase database,
    required String userId,
    required EncryptedFileVault vault,
    required Future<Directory> Function() rootDirectory,
  }) : _database = database,
       _userId = userId,
       _vault = vault,
       _rootDirectory = rootDirectory;

  static const _cacheType = 'reader-image';
  static const _maxImageBytes = FileSizeThresholds.readerImageMaxBytes;
  static final RegExp _storageKeyPattern = RegExp(r'^[0-9a-f]{64}$');

  final LocalDatabase _database;
  final String _userId;
  final EncryptedFileVault _vault;
  final Future<Directory> Function() _rootDirectory;
  final Map<String, Future<void>> _writes = <String, Future<void>>{};

  @override
  Future<void> saveImage({
    required String itemId,
    required String imagePath,
    required Uint8List bytes,
    String mimeType = 'image/png',
  }) {
    if (bytes.length > _maxImageBytes) {
      throw const FormatException('阅读图片超过离线缓存大小限制');
    }
    final lockKey = '$itemId\u0000$imagePath';
    return _serialize(
      lockKey,
      () => _saveImage(
        itemId: itemId,
        imagePath: imagePath,
        bytes: bytes,
        mimeType: mimeType,
      ),
    );
  }

  Future<void> _saveImage({
    required String itemId,
    required String imagePath,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final storageKey = await _storageKey(itemId, imagePath);
    final file = await _fileFor(storageKey);
    final existing = await _selectOne(itemId, imagePath);
    await _vault.encryptBytes(
      bytes: bytes,
      destination: file,
      context: _context(itemId, imagePath),
    );
    final now = DateTime.now();
    try {
      await _database
          .into(_database.cachedReaderImages)
          .insertOnConflictUpdate(
            CachedReaderImagesCompanion.insert(
              userId: _userId,
              itemId: itemId,
              imagePath: imagePath,
              mimeType: Value(mimeType),
              storageKey: storageKey,
              sizeBytes: bytes.length,
              cachedAt: now,
              lastAccessedAt: now,
            ),
          );
    } on Exception {
      if (existing == null && await file.exists()) {
        await file.delete();
      }
      rethrow;
    }
  }

  @override
  Future<Uint8List?> loadImage({
    required String itemId,
    required String imagePath,
  }) async {
    final row = await _selectOne(itemId, imagePath);
    if (row == null) return null;
    File? file;
    try {
      file = await _fileFor(row.storageKey);
      if (!await file.exists()) {
        await _deleteRow(row);
        return null;
      }
      final bytes = await _vault.decryptToBytes(
        source: file,
        context: _context(itemId, imagePath),
        maxBytes: _maxImageBytes,
      );
      if (bytes.length != row.sizeBytes) {
        throw const FormatException('阅读图片缓存长度不一致');
      }
      await (_database.update(_database.cachedReaderImages)..where(
        (table) =>
            table.userId.equals(_userId) &
            table.itemId.equals(itemId) &
            table.imagePath.equals(imagePath),
      )).write(
        CachedReaderImagesCompanion(lastAccessedAt: Value(DateTime.now())),
      );
      return bytes;
    } on Exception {
      if (file != null) {
        await _deleteFile(file);
      }
      await _deleteRow(row);
      return null;
    }
  }

  @override
  Future<void> deleteForItem(String itemId) async {
    final rows =
        await (_database.select(_database.cachedReaderImages)..where(
          (table) => table.userId.equals(_userId) & table.itemId.equals(itemId),
        )).get();
    await _deleteFilesInBackground(rows);
    await (_database.delete(_database.cachedReaderImages)..where(
      (table) => table.userId.equals(_userId) & table.itemId.equals(itemId),
    )).go();
  }

  @override
  Future<void> cleanOld({int maxAgeDays = 30}) async {
    if (maxAgeDays < 0) {
      throw ArgumentError.value(maxAgeDays, 'maxAgeDays', '缓存有效天数不能为负数');
    }
    final cutoff = DateTime.now().subtract(Duration(days: maxAgeDays));
    final rows =
        await (_database.select(_database.cachedReaderImages)..where(
          (table) =>
              table.userId.equals(_userId) &
              table.lastAccessedAt.isSmallerThanValue(cutoff),
        )).get();
    await _deleteFiles(rows);
    await (_database.delete(_database.cachedReaderImages)..where(
      (table) =>
          table.userId.equals(_userId) &
          table.lastAccessedAt.isSmallerThanValue(cutoff),
    )).go();
  }

  @override
  Future<void> clearAll() async {
    final rows =
        await (_database.select(_database.cachedReaderImages)
          ..where((table) => table.userId.equals(_userId))).get();
    await _deleteFiles(rows);
    await (_database.delete(_database.cachedReaderImages)
      ..where((table) => table.userId.equals(_userId))).go();
  }

  Future<CachedReaderImage?> _selectOne(String itemId, String imagePath) {
    return (_database.select(_database.cachedReaderImages)..where(
      (table) =>
          table.userId.equals(_userId) &
          table.itemId.equals(itemId) &
          table.imagePath.equals(imagePath),
    )).getSingleOrNull();
  }

  /// 将文件删除循环移出 UI isolate 执行，避免大量加密图片文件删除阻塞界面。
  /// DB 的 select/delete 留在原处（已在后台 isolate），此处仅处理文件系统。
  Future<void> _deleteFilesInBackground(List<CachedReaderImage> rows) async {
    if (rows.isEmpty) {
      return;
    }
    final root = await _cacheRoot();
    final storageKeys = <String>[];
    for (final row in rows) {
      if (_storageKeyPattern.hasMatch(row.storageKey)) {
        storageKeys.add(row.storageKey);
      }
    }
    if (storageKeys.isEmpty) {
      return;
    }
    await Isolate.run(() {
      for (final key in storageKeys) {
        final filePath = p.normalize(p.join(root.path, '$key.onf'));
        if (!p.isWithin(root.path, filePath)) {
          continue;
        }
        final file = File(filePath);
        if (file.existsSync()) {
          file.deleteSync();
        }
      }
    });
  }

  Future<void> _deleteFiles(List<CachedReaderImage> rows) async {
    for (final row in rows) {
      try {
        final file = await _fileFor(row.storageKey);
        await _deleteFile(file);
      } on FormatException {
        // 非法存储键没有可安全删除的文件路径，索引由调用方统一删除。
      }
    }
  }

  Future<void> _deleteRow(CachedReaderImage row) {
    return (_database.delete(_database.cachedReaderImages)..where(
      (table) =>
          table.userId.equals(row.userId) &
          table.itemId.equals(row.itemId) &
          table.imagePath.equals(row.imagePath),
    )).go();
  }

  Future<void> _deleteFile(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> _fileFor(String storageKey) async {
    if (!_storageKeyPattern.hasMatch(storageKey)) {
      throw const FormatException('阅读图片存储键无效');
    }
    final root = await _cacheRoot();
    final filePath = p.normalize(p.join(root.path, '$storageKey.onf'));
    if (!p.isWithin(root.path, filePath)) {
      throw const FormatException('阅读图片缓存路径越界');
    }
    return File(filePath);
  }

  Future<Directory> _cacheRoot() async {
    final root = await _rootDirectory();
    final encodedUserId = base64UrlEncode(
      utf8.encode(_userId),
    ).replaceAll('=', '');
    final directory = Directory(
      p.join(root.path, 'reader_image_cache_v2', encodedUserId),
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<String> _storageKey(String itemId, String imagePath) async {
    final hash = await Sha256().hash(
      utf8.encode('$_userId\u0000$itemId\u0000$imagePath'),
    );
    return hash.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  OfflineFileContext _context(String itemId, String imagePath) {
    return OfflineFileContext(
      userId: _userId,
      cacheType: _cacheType,
      businessId: '$itemId\u0000$imagePath',
    );
  }

  Future<void> _serialize(String key, Future<void> Function() operation) {
    final previous = _writes[key];
    final current = _runAfter(previous, operation);
    _writes[key] = current;
    return current.whenComplete(() {
      if (identical(_writes[key], current)) {
        _writes.remove(key);
      }
    });
  }

  Future<void> _runAfter(
    Future<void>? previous,
    Future<void> Function() operation,
  ) async {
    if (previous != null) {
      try {
        await previous;
      } on Exception {
        // 前一次写入失败不阻塞同一图片的后续重试。
      }
    }
    await operation();
  }
}
