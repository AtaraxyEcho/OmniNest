import 'package:file_picker/file_picker.dart' as file_picker;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

typedef MediaImportWindowsPicker =
    Future<List<XFile>> Function(List<String> extensions);

typedef MediaImportSelectorPicker =
    Future<List<XFile>> Function(List<XTypeGroup> acceptedTypeGroups);

/// 按平台选择媒体导入文件选择器，避免 Widget 直接依赖平台插件。
class MediaImportFilePickerAdapter {
  const MediaImportFilePickerAdapter({
    required this.isWindows,
    required this.windowsPicker,
    required this.selectorPicker,
  });

  final bool isWindows;
  final MediaImportWindowsPicker windowsPicker;
  final MediaImportSelectorPicker selectorPicker;

  Future<List<XFile>> pick(List<XTypeGroup> acceptedTypeGroups) {
    if (isWindows) {
      return windowsPicker(mediaImportFilePickerExtensions(acceptedTypeGroups));
    }
    return selectorPicker(acceptedTypeGroups);
  }
}

Future<List<XFile>> pickMediaImportFiles(List<XTypeGroup> acceptedTypeGroups) {
  final adapter = MediaImportFilePickerAdapter(
    isWindows: !kIsWeb && defaultTargetPlatform == TargetPlatform.windows,
    windowsPicker: _pickWindowsFiles,
    selectorPicker: _pickFilesWithSelector,
  );
  return adapter.pick(acceptedTypeGroups);
}

Future<List<XFile>> _pickFilesWithSelector(
  List<XTypeGroup> acceptedTypeGroups,
) {
  return openFiles(acceptedTypeGroups: acceptedTypeGroups);
}

Future<List<XFile>> _pickWindowsFiles(List<String> extensions) async {
  final files = await file_picker.FilePicker.pickFiles(
    type:
        extensions.isEmpty
            ? file_picker.FileType.any
            : file_picker.FileType.custom,
    allowedExtensions: extensions.isEmpty ? null : extensions,
  );
  return files.map((file) => file.xFile).toList(growable: false);
}

List<String> mediaImportFilePickerExtensions(
  List<XTypeGroup> acceptedTypeGroups,
) {
  final seen = <String>{};
  final extensions = <String>[];
  for (final group in acceptedTypeGroups) {
    for (final extension in group.extensions ?? const <String>[]) {
      final normalized =
          extension.trim().replaceFirst(RegExp(r'^\.'), '').toLowerCase();
      if (normalized.isNotEmpty && seen.add(normalized)) {
        extensions.add(normalized);
      }
    }
  }
  return extensions;
}
