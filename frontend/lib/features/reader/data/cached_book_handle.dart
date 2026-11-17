import 'dart:io';
import 'dart:typed_data';

/// 阅读缓存的会话级解析句柄。
///
/// Web 平台持有受限内存字节，原生平台惰性打开会话明文文件。
class CachedBookHandle {
  CachedBookHandle.memory(Uint8List bytes)
    : _memoryBytes = bytes,
      _openFile = null,
      _closeFile = null;

  CachedBookHandle.file({
    required Future<File> Function() openFile,
    required Future<void> Function(File? openedFile) closeFile,
  }) : _memoryBytes = null,
       _openFile = openFile,
       _closeFile = closeFile;

  final Uint8List? _memoryBytes;
  final Future<File> Function()? _openFile;
  final Future<void> Function(File? openedFile)? _closeFile;

  Future<File>? _openedFile;
  bool _closed = false;

  /// 是否使用内存字节作为解析源。
  bool get isMemory => _memoryBytes != null;

  /// 内存解析源；原生文件句柄返回空值。
  Uint8List? get memoryBytes => _memoryBytes;

  /// 解析源是否为空。
  bool get isEmpty => _memoryBytes?.isEmpty ?? false;

  /// 惰性打开原生会话明文文件并返回路径。
  Future<String?> openFilePath() async {
    if (_closed) {
      throw StateError('阅读缓存句柄已关闭');
    }
    final opener = _openFile;
    if (opener == null) return null;
    final file = await (_openedFile ??= opener());
    return file.path;
  }

  /// 在容量限制内读取完整字节，供 TXT 和 Web 解析使用。
  Future<Uint8List> readBytes({required int maxBytes}) async {
    if (maxBytes <= 0) {
      throw ArgumentError.value(maxBytes, 'maxBytes', '读取上限必须为正数');
    }
    final bytes = _memoryBytes;
    if (bytes != null) {
      if (bytes.length > maxBytes) {
        throw const FormatException('阅读文件超过整包解析上限');
      }
      return bytes;
    }
    final path = await openFilePath();
    if (path == null) return Uint8List(0);
    final file = File(path);
    if (await file.length() > maxBytes) {
      throw const FormatException('阅读文件超过整包解析上限');
    }
    return file.readAsBytes();
  }

  /// 关闭句柄并清理会话明文文件。
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    File? file;
    final opened = _openedFile;
    if (opened != null) {
      try {
        file = await opened;
      } catch (_) {
        file = null;
      }
    }
    await _closeFile?.call(file);
  }
}
