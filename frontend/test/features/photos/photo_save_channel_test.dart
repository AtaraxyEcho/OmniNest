import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/photos/platform/photo_save_channel.dart';
import 'package:omninest/platform/platform_capabilities.dart';

void main() {
  group('photo export channel', () {
    test('保存对话框能力跟随 supportsFileSystemSaveDialog', () {
      expect(
        photoExportUsesSaveDialog,
        PlatformCapabilities.current().supportsFileSystemSaveDialog,
      );
    });

    test('PhotoExportCancelled 为独立结果类型', () {
      const result = PhotoExportCancelled();
      expect(result, isA<PhotoExportResult>());
      expect(result, isNot(isA<PhotoExportSaved>()));
      expect(result, isNot(isA<PhotoExportShared>()));
    });

    test('PhotoExportSaved 携带落盘路径', () {
      const result = PhotoExportSaved('/tmp/a.jpg');
      expect(result.path, '/tmp/a.jpg');
    });
  });
}
