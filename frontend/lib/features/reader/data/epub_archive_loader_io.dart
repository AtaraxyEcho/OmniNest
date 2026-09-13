import 'package:archive/archive_io.dart';
import 'package:omninest/features/reader/data/epub_archive_source.dart';

/// 从原生文件系统打开延迟解压的 EPUB 归档。
EpubArchiveSource openEpubArchiveFile(String path) {
  final input = InputFileStream(path);
  try {
    final archive = ZipDecoder().decodeStream(input);
    return _IoEpubArchiveSource(input: input, archive: archive);
  } catch (_) {
    input.closeSync();
    rethrow;
  }
}

class _IoEpubArchiveSource implements EpubArchiveSource {
  _IoEpubArchiveSource({required this.input, required this.archive});

  final InputFileStream input;

  @override
  final Archive archive;

  @override
  void close() {
    input.closeSync();
  }
}
