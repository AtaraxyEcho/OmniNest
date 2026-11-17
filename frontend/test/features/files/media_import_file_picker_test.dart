import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/files/application/media_import_file_picker.dart';

void main() {
  test('归一化并去重文件扩展名', () {
    final extensions = mediaImportFilePickerExtensions(<XTypeGroup>[
      XTypeGroup(
        label: 'Photos',
        extensions: <String>['.JPG', 'png ', 'jpg', '  ', '.HEIC'],
      ),
      XTypeGroup(label: 'More', extensions: <String>['PNG', 'gif']),
    ]);

    expect(extensions, <String>['jpg', 'png', 'heic', 'gif']);
  });

  test('Windows 使用 file_picker 路由并传递扩展名', () async {
    List<String>? capturedExtensions;
    var selectorCalled = false;
    final expected = <XFile>[XFile('photo.jpg', name: 'photo.jpg')];
    final adapter = MediaImportFilePickerAdapter(
      isWindows: true,
      windowsPicker: (extensions) async {
        capturedExtensions = extensions;
        return expected;
      },
      selectorPicker: (_) async {
        selectorCalled = true;
        return const <XFile>[];
      },
    );

    final files = await adapter.pick(<XTypeGroup>[
      XTypeGroup(label: 'Photos', extensions: <String>['jpg', 'png']),
    ]);

    expect(files, same(expected));
    expect(capturedExtensions, <String>['jpg', 'png']);
    expect(selectorCalled, isFalse);
  });

  test('非 Windows 使用 file_selector 路由并保留类型组', () async {
    List<XTypeGroup>? capturedGroups;
    var windowsCalled = false;
    final expected = <XFile>[XFile('photo.png', name: 'photo.png')];
    final groups = <XTypeGroup>[
      XTypeGroup(label: 'Photos', extensions: <String>['png']),
    ];
    final adapter = MediaImportFilePickerAdapter(
      isWindows: false,
      windowsPicker: (_) async {
        windowsCalled = true;
        return const <XFile>[];
      },
      selectorPicker: (value) async {
        capturedGroups = value;
        return expected;
      },
    );

    final files = await adapter.pick(groups);

    expect(files, same(expected));
    expect(capturedGroups, same(groups));
    expect(windowsCalled, isFalse);
  });
}
