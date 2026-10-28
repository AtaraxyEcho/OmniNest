import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// presentation 层不得再直接触碰平台文件选择与 `dart:io`。
///
/// 选择文件一律走 `lib/platform/file_pick.dart`：插件类型、本地路径与 Web 内存字节的分支
/// 都收在平台层，否则同一套 `kIsWeb`/`File(path)` 判断会在各 feature 里各写一遍。
///
/// 已知未覆盖：`package:file_selector/` 的 `openFile()`/`openFiles()` 直调与拖放面板
/// 仍在 5 个 presentation 文件里，纳入判据前要先给 FilePick 补对应出口。
void main() {
  const allowedViolations = <String>{};

  test('presentation 层不直接依赖 file_picker、image_picker、dart:io 或裸 XFile 构造', () {
    final found = <String>{};

    for (final entity in Directory('lib/features').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final path = entity.path.replaceAll('\\', '/');
      if (!path.contains('/presentation/')) {
        continue;
      }
      final content = entity.readAsStringSync();
      if (RegExp("import 'package:file_picker/").hasMatch(content)) {
        found.add('FILE_PICKER_IMPORT $path');
      }
      if (RegExp("import 'package:image_picker/").hasMatch(content)) {
        found.add('IMAGE_PICKER_IMPORT $path');
      }
      if (RegExp("import 'dart:io'").hasMatch(content)) {
        found.add('DART_IO_IMPORT $path');
      }
      if (content.replaceAll('toXFile(', '').contains('XFile(')) {
        found.add('RAW_XFILE_CONSTRUCTION $path');
      }
    }

    final unexpected = found.difference(allowedViolations).toList()..sort();
    final stale = allowedViolations.difference(found).toList()..sort();

    expect(unexpected, isEmpty, reason: '新增平台直调：\n${unexpected.join('\n')}');
    expect(stale, isEmpty, reason: '以下存量已修复，请从清单删除：\n${stale.join('\n')}');
  });
}
