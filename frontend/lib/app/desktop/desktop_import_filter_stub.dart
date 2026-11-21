import 'package:file_selector/file_selector.dart';

/// Web 等无本机文件系统的平台：目录遍历按空结果降级，浏览器不会暴露目录内容。
Future<List<XFile>> listFilesUnderDirectory(
  String dirPath, {
  required int maxCount,
}) async {
  return const <XFile>[];
}

/// Web 等无本机文件系统的平台：无法探查路径类型，恒按非目录处理。
Future<bool> isDirectoryPath(String path) async {
  return false;
}

/// 取路径最后一段作为文件名（同时兼容 Windows 与 POSIX 分隔符）。
String baseNameOfPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  return slash < 0 ? normalized : normalized.substring(slash + 1);
}
