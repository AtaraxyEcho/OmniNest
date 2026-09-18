import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _maximumSourceLines = 1200;

/// 0.1.0 发布前登记的存量超长源码；禁止新增，拆分完成后从清单移除。
const _allowedOversizedSources = <String>{
  'lib/features/music/presentation/deck/music_deck_content.dart',
  'lib/features/reader/presentation/pages/reader_item_detail_page.dart',
  'lib/features/reader/presentation/pages/reader_view_page.dart',
  'lib/features/video/application/movie_controller.dart',
  'lib/features/video/presentation/pages/movie_detail_page.dart',
  'test/features/music/music_controller_test.dart',
};

void main() {
  test('手写 Dart 源码不超过 1200 行', () async {
    final oversizedSources = <String>[];
    for (final sourceRoot in const <String>['lib', 'test']) {
      await for (final entity in Directory(sourceRoot).list(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final normalizedPath = entity.path.replaceAll('\\', '/');
        if (_isGeneratedSource(normalizedPath)) {
          continue;
        }
        final lineCount = (await entity.readAsLines()).length;
        if (lineCount > _maximumSourceLines &&
            !_allowedOversizedSources.contains(normalizedPath)) {
          oversizedSources.add('$normalizedPath lines=$lineCount');
        }
      }
    }
    oversizedSources.sort();

    expect(
      oversizedSources,
      isEmpty,
      reason: '手写 Dart 源码超过 1200 行，请按职责拆分：\n${oversizedSources.join('\n')}',
    );
  });
}

bool _isGeneratedSource(String path) {
  return path.endsWith('.g.dart') ||
      path.endsWith('.freezed.dart') ||
      path.startsWith('lib/app/l10n/app_localizations');
}
