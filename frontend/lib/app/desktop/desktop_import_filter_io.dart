import 'dart:io';

import 'package:file_selector/file_selector.dart';

/// 本机平台实现：递归列出目录下的普通文件，用于拖拽文件夹与「选择文件夹」导入。
///
/// 单次上限由调用方给定；无读取权限或遍历异常的目录整段跳过，保证其余目录
/// 仍能正常导入。
Future<List<XFile>> listFilesUnderDirectory(
  String dirPath, {
  required int maxCount,
}) async {
  final files = <XFile>[];
  if (dirPath.isEmpty || maxCount <= 0) {
    return files;
  }
  try {
    await for (final entity in Directory(
      dirPath,
    ).list(recursive: true, followLinks: false)) {
      if (files.length >= maxCount) break;
      if (entity is! File) continue;
      final path = entity.path;
      files.add(XFile(path, name: baseNameOfPath(path)));
    }
  } on Object {
    // 跳过无读取权限或遍历异常的目录。
  }
  return files;
}

/// 本机平台实现：判断路径是否为目录。
Future<bool> isDirectoryPath(String path) async {
  if (path.isEmpty) {
    return false;
  }
  try {
    final type = await FileSystemEntity.type(path, followLinks: false);
    return type == FileSystemEntityType.directory;
  } on Object {
    return false;
  }
}

/// 取路径最后一段作为文件名（同时兼容 Windows 与 POSIX 分隔符）。
String baseNameOfPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash < 0 ? normalized : normalized.substring(slash + 1);
}
