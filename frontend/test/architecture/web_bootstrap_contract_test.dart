import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web bootstrap only uses supported Flutter template tokens', () {
    final indexSource = File('web/index.html').readAsStringSync();
    final bootstrapSource = File('web/flutter_bootstrap.js').readAsStringSync();
    final tokens = RegExp(r'\{\{([^}]+)\}\}')
        .allMatches('$indexSource\n$bootstrapSource')
        .map((match) => match.group(1));

    expect(
      tokens,
      everyElement(
        isIn(const <String>{
          'flutter_js',
          'flutter_build_config',
          'flutter_service_worker_version',
        }),
      ),
    );
    expect(indexSource, isNot(contains('flutter_bootstrap_config')));
  });

  test('Web bootstrap loads the self-hosted CanvasKit runtime from the page base', () {
    final bootstrapSource = File('web/flutter_bootstrap.js').readAsStringSync();

    expect(bootstrapSource, contains('{{flutter_js}}'));
    expect(bootstrapSource, contains('{{flutter_build_config}}'));
    // CanvasKit 只允许自托管，且路径跟随 <base href> 以便子路径部署。
    expect(bootstrapSource, contains("document.querySelector('base')"));
    expect(bootstrapSource, contains("baseHref + 'canvaskit/'"));
    expect(bootstrapSource, isNot(contains("canvasKitBaseUrl: '/canvaskit/'")));
    expect(bootstrapSource, isNot(contains('gstatic')));
  });
}
