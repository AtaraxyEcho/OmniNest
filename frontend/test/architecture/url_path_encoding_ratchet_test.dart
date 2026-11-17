import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 高风险动态 URL 段的编码闸门。
///
/// 相册标签、分享令牌、挂载键、角色编码、第三方歌单/歌曲 ID 与章节 ID 都可能包含
/// `/`、`#`、`?`、`%`：裸插值会让请求被截断或路由到别的路径。UUID 形式的实体会被
/// 后端按格式拒绝，不在此闸门范围内；这里只钉住真正用户可控或外部来源的段。
void main() {
  const riskySegments = <String>[
    'tag',
    'key',
    'token',
    'chapterId',
    'mountKey',
    'roleCode',
    'platform',
    'playlistId',
    'songId',
    'catalogKey',
  ];
  final rawSegment = RegExp(
    "'/[^']*\\\$(${riskySegments.join('|')})(?:/|'|\\?)",
  );

  test('features 数据层不得裸插值高风险路径段', () {
    final violations = <String>[];
    for (final entity in Directory('lib/features').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final normalized = entity.path.replaceAll('\\', '/');
      if (!normalized.contains('/data/')) {
        continue;
      }
      final source = entity.readAsStringSync();
      for (final match in rawSegment.allMatches(source)) {
        violations.add('$normalized: ${match.group(0)}');
      }
    }
    expect(
      violations,
      isEmpty,
      reason: '动态路径段必须使用 Uri.encodeComponent：\n${violations.join('\n')}',
    );
  });
}
