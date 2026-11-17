import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('阅读封面统一通过认证图片组件加载', () {
    final readerPresentation = Directory('lib/features/reader/presentation')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    final source = readerPresentation
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(source, isNot(contains('resolveReaderUrl(')));
    expect(
      RegExp(r'Image\.network\(\s*item\.coverUrl!').hasMatch(source),
      isFalse,
    );
    expect(source, contains('AuthCoverImage('));
  });
}
