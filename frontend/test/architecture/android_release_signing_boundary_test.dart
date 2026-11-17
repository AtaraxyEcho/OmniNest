import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android release 必须显式提供正式签名或本地调试签名开关', () {
    final source = File('android/app/build.gradle.kts').readAsStringSync();

    expect(source, contains('OMNINEST_ANDROID_KEYSTORE_PATH'));
    expect(source, contains('OMNINEST_ANDROID_KEYSTORE_PASSWORD'));
    expect(source, contains('OMNINEST_ANDROID_KEY_ALIAS'));
    expect(source, contains('OMNINEST_ANDROID_KEY_PASSWORD'));
    expect(source, contains('OMNINEST_ALLOW_DEBUG_RELEASE_SIGNING'));
    expect(source, contains('releaseBuildRequested'));
    expect(source, contains('throw GradleException'));
    expect(
      source,
      contains('allowDebugReleaseSigning -> signingConfigs.getByName("debug")'),
    );
    expect(
      source,
      isNot(contains('else -> signingConfigs.getByName("debug")')),
    );
  });
}
