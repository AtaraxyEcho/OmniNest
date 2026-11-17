import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('core 源码不依赖业务 feature', () {
    final violations = <String>[];
    for (final entity in Directory('lib/core').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      if (entity.readAsStringSync().contains('package:omninest/features/')) {
        violations.add(entity.path);
      }
    }

    expect(violations, isEmpty, reason: 'core 只能提供基础能力，不能反向依赖业务 feature');
  });
}
