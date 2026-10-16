import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// 平台文件选择的唯一出口。
///
/// presentation 层只消费 [PickedFile]，不再直接依赖 file_picker、`dart:io` 或 `kIsWeb` 分支；
/// 本地路径与 Web 内存字节的差异全部收在这里。
abstract final class FilePick {
  /// 调用平台相机拍照，用户放弃时返回 null。
  ///
  /// 这里返回 [XFile] 而不是 [PickedFile]：相机产物只有「立刻上传」这一个用途，
  /// 上传链路本身就以 [XFile] 为通货，再包一层不带来任何平台差异收敛。
  static Future<XFile?> pickCameraPhoto({double? maxWidth}) {
    return ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: maxWidth,
    );
  }

  /// 调用平台相机录像，用户放弃时返回 null。
  static Future<XFile?> pickCameraVideo() {
    return ImagePicker().pickVideo(source: ImageSource.camera);
  }

  /// 选择图片，扩展名与类型过滤交由平台原生选择器处理。
  static Future<List<PickedFile>> pickImages({String? dialogTitle}) {
    return _pick(
      type: FileType.image,
      allowedExtensions: null,
      dialogTitle: dialogTitle,
    );
  }

  /// 按扩展名选择文件；`allowedExtensions` 不含点号，如 `['lrc', 'txt']`。
  static Future<List<PickedFile>> pickFiles({
    required List<String> allowedExtensions,
    String? dialogTitle,
  }) {
    return _pick(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      dialogTitle: dialogTitle,
    );
  }

  static Future<List<PickedFile>> _pick({
    required FileType type,
    required List<String>? allowedExtensions,
    String? dialogTitle,
  }) async {
    final picked = await FilePicker.pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
      dialogTitle: dialogTitle,
    );
    return picked.map(PickedFile._fromPlatformFile).toList(growable: false);
  }
}

/// 一次选择结果里的单个文件。
///
/// 字节按需读取：大文件（EPUB/ZIP 之类）只拿路径与大小，不因此整本驻留内存。
final class PickedFile {
  const PickedFile._fromPlatformFile(this._source);

  final PlatformFile _source;

  /// 含扩展名的文件名。
  String get name => _source.name;

  /// 小写、不含点号的扩展名；无扩展名时为 null。
  String? get extension => _source.extension?.toLowerCase();

  /// 本地磁盘路径；Web 或无法寻址时为 null。
  String? get path => _source.path;

  /// 已知大小，未免去读盘时返回 null。
  int? lengthSync() => _source.lengthSync();

  /// 文件大小；无法确定时返回 null。
  Future<int?> length() => _source.length();

  /// 读取整个文件字节；平台只给路径（桌面端的常见形态）时按路径补读一次。
  Future<Uint8List> readBytes() async {
    final bytes = await _source.readAsBytes();
    if (bytes.isNotEmpty) {
      return bytes;
    }
    final localPath = path;
    if (kIsWeb || localPath == null || localPath.isEmpty) {
      return bytes;
    }
    return XFile(localPath).readAsBytes();
  }

  /// 转成可上传的 [XFile]：本地路径优先，Web 或无路径时按字节构造。
  Future<XFile> toXFile({String? mimeType}) async {
    final localPath = path;
    if (!kIsWeb && localPath != null && localPath.isNotEmpty) {
      return XFile(localPath, name: name, mimeType: mimeType);
    }
    final bytes = await readBytes();
    return XFile.fromData(bytes, name: name, mimeType: mimeType);
  }
}
