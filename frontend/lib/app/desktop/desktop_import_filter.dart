import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'desktop_import_filter_stub.dart'
    if (dart.library.io) 'desktop_import_filter_io.dart';

/// 与新版样例 `importFilter.ts` 严格对齐的四大媒体模块枚举。
enum DesktopImportModule { film, photo, music, book }

/// 导入筛选拒绝原因。
enum ImportRejectReason { unsupportedExt, emptyFile }

/// 单条被拦截文件明细（对应样例 `.imp-bad` 列表项）。
class ImportRejectedItem {
  const ImportRejectedItem({
    required this.name,
    required this.reason,
    this.extension = '',
  });

  final String name;
  final ImportRejectReason reason;
  final String extension;
}

/// 待筛选导入候选条目。
class ImportCandidate<T> {
  const ImportCandidate({
    required this.name,
    required this.sizeBytes,
    required this.item,
    this.key,
    this.mimeType,
  });

  final String name;
  final int? sizeBytes;
  final T item;
  final String? key;
  final String? mimeType;
}

/// 导入候选筛选结果。
class ImportFilterResult<T> {
  const ImportFilterResult({
    required this.accepted,
    required this.rejected,
    required this.junkSkipped,
    required this.duplicateCount,
  });

  final List<ImportCandidate<T>> accepted;
  final List<ImportRejectedItem> rejected;
  final int junkSkipped;
  final int duplicateCount;

  List<ImportRejectedItem> get rejectedByExt => rejected
      .where((item) => item.reason == ImportRejectReason.unsupportedExt)
      .toList(growable: false);

  List<ImportRejectedItem> get rejectedEmpty => rejected
      .where((item) => item.reason == ImportRejectReason.emptyFile)
      .toList(growable: false);
}

/// 全模块统一扩展名白名单单一真源（对齐样例 `importFilter.ts` 与后端）。
const Map<DesktopImportModule, List<String>> desktopImportExtensions =
    <DesktopImportModule, List<String>>{
      DesktopImportModule.film: <String>[
        'mkv',
        'mp4',
        'm4v',
        'mov',
        'avi',
        'wmv',
        'flv',
        'webm',
        'ts',
        'm2ts',
        'mpg',
        'mpeg',
        'rmvb',
      ],
      DesktopImportModule.photo: <String>[
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'heic',
        'heif',
        'avif',
        'tif',
        'tiff',
        'bmp',
        'dng',
        'arw',
        'cr2',
        'cr3',
        'nef',
        'raf',
        'orf',
        'rw2',
        'mp4',
        'mov',
        'm4v',
        'avi',
        'webm',
      ],
      DesktopImportModule.music: <String>[
        'flac',
        'mp3',
        'aac',
        'm4a',
        'wav',
        'ogg',
        'opus',
        'wma',
        'ape',
        'aiff',
        'aif',
        'alac',
      ],
      DesktopImportModule.book: <String>['epub', 'txt', 'cbz', 'zip', 'pdf'],
    };

/// 返回指定模块允许的扩展名列表。
List<String> importExtensionsFor(DesktopImportModule module) =>
    desktopImportExtensions[module] ?? const <String>[];

/// 提取文件名的纯小写扩展名（忽略目录前缀与以点开头的隐藏文件名）。
String importExtensionOf(String name) {
  final base = baseNameOfPath(name);
  final dot = base.lastIndexOf('.');
  if (dot <= 0 || dot >= base.length - 1) {
    return '';
  }
  return base.substring(dot + 1).toLowerCase();
}

/// 操作系统隐藏文件或元数据垃圾文件（`.` 开头、`thumbs.db`、`desktop.ini`）。
bool isJunkFile(String name) {
  final base = baseNameOfPath(name);
  if (base.isEmpty) {
    return true;
  }
  if (base.startsWith('.')) {
    return true;
  }
  final lower = base.toLowerCase();
  return lower == 'thumbs.db' || lower == 'desktop.ini';
}

/// 判断文件扩展名或 MIME 类型是否属于指定模块白名单。
bool acceptsImportFile(
  DesktopImportModule module,
  String name, {
  String? mimeType,
}) {
  final ext = importExtensionOf(name);
  if (ext.isNotEmpty && importExtensionsFor(module).contains(ext)) {
    return true;
  }
  final mime = mimeType?.toLowerCase() ?? '';
  if (mime.isEmpty) {
    return false;
  }
  return switch (module) {
    DesktopImportModule.film => mime.startsWith('video/'),
    DesktopImportModule.photo =>
      mime.startsWith('image/') || mime.startsWith('video/'),
    DesktopImportModule.music => mime.startsWith('audio/'),
    DesktopImportModule.book =>
      mime.startsWith('text/') ||
          mime.contains('epub') ||
          mime.contains('pdf') ||
          mime.contains('zip'),
  };
}

/// 对候选文件执行垃圾剔除、扩展名白名单校验、0 字节拦截与去重。
ImportFilterResult<T> filterImportCandidates<T>(
  List<ImportCandidate<T>> items,
  DesktopImportModule module, {
  Set<String> existingKeys = const <String>{},
}) {
  final accepted = <ImportCandidate<T>>[];
  final rejected = <ImportRejectedItem>[];
  final seen = <String>{...existingKeys};
  var junkSkipped = 0;
  var duplicateCount = 0;

  for (final candidate in items) {
    if (isJunkFile(candidate.name)) {
      junkSkipped++;
      continue;
    }
    if (!acceptsImportFile(
      module,
      candidate.name,
      mimeType: candidate.mimeType,
    )) {
      rejected.add(
        ImportRejectedItem(
          name: candidate.name,
          reason: ImportRejectReason.unsupportedExt,
          extension: importExtensionOf(candidate.name),
        ),
      );
      continue;
    }
    if (candidate.sizeBytes != null && candidate.sizeBytes == 0) {
      rejected.add(
        ImportRejectedItem(
          name: candidate.name,
          reason: ImportRejectReason.emptyFile,
          extension: importExtensionOf(candidate.name),
        ),
      );
      continue;
    }
    final key = candidate.key ?? candidate.name;
    if (!seen.add(key)) {
      duplicateCount++;
      continue;
    }
    accepted.add(candidate);
  }

  return ImportFilterResult<T>(
    accepted: accepted,
    rejected: rejected,
    junkSkipped: junkSkipped,
    duplicateCount: duplicateCount,
  );
}

/// 递归展开拖入项（同时支持文件与 [DropItemDirectory] 嵌套目录），单次上限 5000。
Future<List<XFile>> expandDroppedItems(
  List<DropItem> items, {
  int maxCount = 5000,
}) async {
  final result = <XFile>[];
  final seenPaths = <String>{};

  Future<void> walkDropItem(DropItem item) async {
    if (result.length >= maxCount) return;
    if (item is DropItemDirectory) {
      if (item.children.isNotEmpty) {
        for (final child in item.children) {
          if (result.length >= maxCount) return;
          await walkDropItem(child);
        }
        return;
      }
      if (!kIsWeb && item.path.isNotEmpty) {
        await _walkFileSystemDirectory(
          item.path,
          result,
          seenPaths,
          maxCount: maxCount,
        );
      }
      return;
    }
    if (!kIsWeb && item.path.isNotEmpty) {
      if (await isDirectoryPath(item.path)) {
        await _walkFileSystemDirectory(
          item.path,
          result,
          seenPaths,
          maxCount: maxCount,
        );
        return;
      }
    }
    final pathKey = item.path.isNotEmpty ? item.path : item.name;
    if (seenPaths.add(pathKey)) {
      result.add(item);
    }
  }

  for (final item in items) {
    if (result.length >= maxCount) break;
    await walkDropItem(item);
  }
  return result;
}

/// 递归展开本机选中的文件夹路径，单次上限 5000。
Future<List<XFile>> expandDirectoryPath(
  String directoryPath, {
  int maxCount = 5000,
}) async {
  if (kIsWeb || directoryPath.isEmpty) {
    return const <XFile>[];
  }
  final result = <XFile>[];
  final seenPaths = <String>{};
  await _walkFileSystemDirectory(
    directoryPath,
    result,
    seenPaths,
    maxCount: maxCount,
  );
  return result;
}

Future<void> _walkFileSystemDirectory(
  String dirPath,
  List<XFile> out,
  Set<String> seenPaths, {
  required int maxCount,
}) async {
  if (out.length >= maxCount) return;
  final files = await listFilesUnderDirectory(
    dirPath,
    maxCount: maxCount - out.length,
  );
  for (final file in files) {
    if (out.length >= maxCount) break;
    if (seenPaths.add(file.path)) {
      out.add(file);
    }
  }
}
