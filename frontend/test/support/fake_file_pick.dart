import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart' show XFile;

/// widget/单元用例用的 file_picker 平台替身。
///
/// `FilePicker.pickFiles` 是静态门面，内部转发到 `FilePickerPlatform.instance`；
/// 该抽象类的构造函数会把平台令牌交给 `PlatformInterface`，所以只有继承它的替身
/// 能通过 `instance` 赋值时的令牌校验。
final class FakeFilePick extends FilePickerPlatform {
  FakeFilePick({this.files = const [], this.error});

  /// 选择结果；[error] 非空时改为抛出该异常。
  final List<PlatformFile> files;

  /// 让选择动作抛出该异常，用于验证异常有调用方出口而不是落进全局 Zone。
  final Object? error;

  /// 最近一次调用收到的参数，便于断言类型、扩展名过滤与标题。
  List<String>? lastAllowedExtensions;
  FileType? lastType;
  String? lastDialogTitle;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) {
    lastDialogTitle = dialogTitle;
    lastAllowedExtensions = allowedExtensions;
    lastType = type;
    if (error != null) {
      return Future<List<PlatformFile>>.error(error!);
    }
    return Future<List<PlatformFile>>.value(files);
  }
}

/// 安装替身，并记住如何还原全局平台实例。
FilePickGuard installFilePick({
  List<PlatformFile> files = const [],
  Object? error,
}) {
  final fake = FakeFilePick(files: files, error: error);
  final previous = FilePickerPlatform.instance;
  FilePickerPlatform.instance = fake;
  return FilePickGuard._(previous, fake);
}

/// 替身的安装句柄：用例结束时必须 [restore]，否则会污染同进程后续用例。
final class FilePickGuard {
  FilePickGuard._(this._previous, this.fake);

  final FilePickerPlatform _previous;

  /// 已安装的替身，用于读取调用参数。
  final FakeFilePick fake;

  void restore() {
    FilePickerPlatform.instance = _previous;
  }
}

/// 内存态的已选文件：不落盘，字节直接给定。
final class FakePickedPlatformFile extends PlatformFile {
  FakePickedPlatformFile({required this.name, Uint8List? bytes, this.path})
    : bytes = bytes ?? Uint8List(0);

  @override
  final String name;

  @override
  final String? path;

  /// 供用例断言的字节内容。
  final Uint8List bytes;

  @override
  Uri get uri => path != null ? Uri.file(path!) : Uri.parse('memory://$name');

  /// 内存态句柄：Web 端真实实现同样持有 Blob/内存字节，不落盘。
  @override
  XFile get xFile => XFile.fromData(bytes, name: name);

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  Stream<Uint8List> readAsByteStream() async* {
    yield bytes;
  }

  @override
  int? lengthSync() => bytes.length;

  @override
  Future<int?> length() async => bytes.length;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError('${invocation.memberName}');
  }
}
