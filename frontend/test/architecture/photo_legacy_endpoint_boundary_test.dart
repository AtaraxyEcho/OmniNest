import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _legacyPhotoEndpointLiterals = <String>{
  r'/photos',
  r'/photos/favorites',
  r'/photos/timeline',
  r'/photos/groups',
  r'/admin/photos/import/candidates',
  r'/photos/batch/$taskId/download',
};

void main() {
  test('前端生产代码不得回退到照片旧全量或旧下载端点', () {
    final violations = <String>[];
    for (final entity in Directory(
      'lib/features/photos/data',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final source = entity.readAsStringSync();
      for (final endpoint in _legacyPhotoEndpointLiterals) {
        if (source.contains("'$endpoint'") || source.contains('"$endpoint"')) {
          final path = entity.path.replaceAll('\\', '/');
          violations.add('$path -> $endpoint');
        }
      }
    }
    violations.sort();

    expect(
      violations,
      isEmpty,
      reason: '发现照片旧端点调用，请使用分页端点或完整下载票据：\n${violations.join('\n')}',
    );
  });
}
