import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android 正式发布脚本必须验证 AAB 签名证书并输出摘要', () {
    final source =
        File('scripts/build_signed_android_release.ps1').readAsStringSync();

    expect(source, contains(r'$ExpectedCertificateSha256'));
    expect(source, contains('OMNINEST_ANDROID_KEYSTORE_PATH'));
    expect(source, contains('OMNINEST_ANDROID_KEYSTORE_PASSWORD'));
    expect(source, contains('OMNINEST_ANDROID_KEY_ALIAS'));
    expect(source, contains('OMNINEST_ANDROID_KEY_PASSWORD'));
    expect(source, contains('OMNINEST_ALLOW_DEBUG_RELEASE_SIGNING'));
    // release 必须显式携带 API 基地址（environment.fromDefines fail-fast 契约）。
    expect(source, contains(r'[string]$ApiBaseUrl'));
    expect(
      source,
      contains("'build', 'appbundle', '--release', '--no-pub'"),
    );
    expect(source, contains(r'--dart-define=OMNINEST_API_BASE_URL=$ApiBaseUrl'));
    expect(source, contains("@('-verify', \$bundle)"));
    expect(source, contains("'-printcert'"));
    expect(source, contains("'-jarfile' \$bundle"));
    expect(source, contains(r"'SHA256:\s*([0-9A-F:]{95})'"));
    expect(source, contains('-Algorithm SHA256'));
    expect(source, contains('android-release.json'));
    expect(source, isNot(contains('storePassword =')));
  });
}
