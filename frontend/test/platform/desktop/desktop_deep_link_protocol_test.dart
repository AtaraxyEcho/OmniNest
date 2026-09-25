import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/platform/desktop/desktop_shell_bootstrap_io.dart';

void main() {
  test('Linux desktop 条目声明 omninest 协议并以 %u 传入深链', () {
    final entry = buildLinuxDesktopEntry('/opt/omninest/omninest');
    expect(entry, contains('[Desktop Entry]'));
    expect(entry, contains('Type=Application'));
    expect(entry, contains('MimeType=x-scheme-handler/omninest;'));
    expect(entry, contains('Exec="/opt/omninest/omninest" "%u"'));
    expect(entry, contains('Terminal=false'));
  });
}
