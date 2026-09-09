import 'package:file_picker/file_picker.dart';
import 'package:omninest/core/utils/platform_helper.dart';

/// 选中的待上传背景文件,平台差异(Web 流式 / 桌面移动路径)收敛在此。
class BackdropPickedFile {
  const BackdropPickedFile({
    required this.name,
    required this.size,
    this.path,
    this.readStream,
  });

  /// 文件名(含扩展名)。
  final String name;

  /// 文件大小,单位字节。
  final int size;

  /// 本机绝对路径;仅桌面/移动可用。
  final String? path;

  /// 分块读取流;Web 平台上传使用,避免整载内存。
  final Stream<List<int>>? readStream;

  /// 是否基于流上传(Web)。
  bool get isStreamBased => path == null || path!.isEmpty;
}

/// 背景素材文件选择器端口。
abstract class BackdropFilePicker {
  Future<List<BackdropPickedFile>> pick();
}

/// 默认实现:file_picker。Web 必须 withReadStream(withData:false 在 Web 会把
/// 文件退化为 base64 data URL 整载内存);桌面/移动由 file_picker 提供路径。
class DefaultBackdropFilePicker implements BackdropFilePicker {
  const DefaultBackdropFilePicker();

  static const List<String> allowedExtensions = [
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'mp4',
    'webm',
    'mov',
    'm4v',
  ];

  @override
  Future<List<BackdropPickedFile>> pick() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
      withData: false,
      withReadStream: true,
    );
    final files = result?.files ?? const <PlatformFile>[];
    return files
        .map(
          (file) => BackdropPickedFile(
            name: file.name,
            size: file.size,
            path: isWebPlatform ? null : file.path,
            readStream: file.readStream,
          ),
        )
        .toList(growable: false);
  }
}
