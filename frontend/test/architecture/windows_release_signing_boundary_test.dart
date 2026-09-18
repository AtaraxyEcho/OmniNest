import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows 正式发布脚本必须完成签名时间戳验证和摘要输出', () {
    final source =
        File('scripts/build_signed_windows_release.ps1').readAsStringSync();

    expect(source, contains(r"[ValidatePattern('^[0-9A-Fa-f]{40}$')]"));
    expect(source, contains(r'$CertificateThumbprint'));
    expect(source, contains(r'$TimestampUrl'));
    // release 必须显式携带 API 基地址（environment.fromDefines fail-fast 契约）。
    expect(source, contains(r'[string]$ApiBaseUrl'));
    expect(source, contains("'build', 'windows', '--release', '--no-pub'"));
    expect(source, contains(r'--dart-define=OMNINEST_API_BASE_URL=$ApiBaseUrl'));
    expect(source, contains("'/fd', 'SHA256'"));
    expect(source, contains("'/tr', \$TimestampUrl"));
    expect(source, contains("'/td', 'SHA256'"));
    expect(source, contains("@('verify', '/pa', '/all', '/v'"));
    expect(source, contains('Get-AuthenticodeSignature'));
    expect(source, contains(r"$signature.Status -ne 'Valid'"));
    expect(source, contains('-Algorithm SHA256'));
    expect(source, contains('windows-release.json'));
    expect(source, isNot(contains('CertificatePassword')));
  });
}
