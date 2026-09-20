import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows 正式发布脚本必须完成签名时间戳验证和摘要输出', () {
    final source =
        File('scripts/build_signed_windows_release.ps1').readAsStringSync();

    expect(source, contains(r"[ValidatePattern('^[0-9A-Fa-f]{40}$')]"));
    expect(source, contains(r'$CertificateThumbprint'));
    expect(source, contains(r'$TimestampUrl'));
    // ApiBaseUrl 可选：不传构建通用包（首启引导配置），传入则作为预置。
    expect(source, contains(r'[string]$ApiBaseUrl'));
    expect(source, contains(r'[switch]$RequireHttps'));
    expect(source, contains(r'--dart-define=OMNINEST_REQUIRE_HTTPS=true'));
    expect(source, contains('-RequireHttps 与 http:// 开头的 -ApiBaseUrl 互斥'));
    expect(source, contains("'build', 'windows', '--release', '--no-pub'"));
    expect(
      source,
      contains(r'--dart-define=OMNINEST_API_BASE_URL=$ApiBaseUrl'),
    );
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
