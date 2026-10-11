// 模块页入口的导航方式棘轮。
//
// `context.go('/music'|'/photos'|'/video'|'/notifications'|'/reader/items|comics|pdfs')`
// 会把整条导航栈换成目标位置：目标页成为栈底，之后的系统返回（Android 边缘
// 手势、Web 后退键）没有任何可弹层，引擎按「无路由可退」处理——真机表现就是
// 直接退出应用。进二级页只有 `push` 才留得住来路，空间之间的同级切换才用
// go（或 goBranch），而那四类路径不在此列。
//
// 逐文件计数并与基线比对：新增入口写成 go、或删掉兜底的 canPop 判断都会红。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 指向模块页与内容详情的 `go` 调用。
final _moduleGo = RegExp(
  r'\.go\(\s*[\x22\x27]/(music|photos|video|notifications|reader/(items|comics|pdfs))',
);

/// 存量允许位置与条数：要么是被 canPop 保护的最后兜底，要么根本不在移动路径上。
/// 位置消失（页面删除或改成 push）时同步收紧这张表，不要往上加。
const _baseline = <String, int>{
  // now-playing 关闭回调：canPop 为假（深链直入）时才回落 go。
  'lib/app/router.dart': 1,
  'lib/features/video/presentation/pages/movie_player_page.dart': 1,
  'lib/features/reader/presentation/pages/comic_reader_page.dart': 1,
  'lib/features/reader/presentation/pages/reader_metadata_edit_page.dart': 1,
  'lib/features/reader/presentation/widgets/reader_view_page_controls_mixin.dart':
      1,
  // 桌面门户的视觉外壳：不托管在移动壳层里，退出路径不是系统返回。
  'lib/features/portal/presentation/widgets/portal_desktop_visual_shells.dart':
      1,
  // 以下三个文件当前没有任何 import（存量旧门户卡片与被 mobile_search_page
  // 取代的结果卡），保留计数只为锁住"别把它们重新接回移动端"。
  'lib/features/portal/presentation/widgets/continue_watching_widget.dart': 1,
  'lib/features/portal/presentation/widgets/recent_photos_widget.dart': 1,
  'lib/features/video/presentation/widgets/movie_continue.dart': 1,
  'lib/features/search/presentation/widgets/search_result_tile.dart': 4,
};

/// canPop 兜底所在文件：go 必须继续待在上一个判断为假的分支里。
const _guardedFallbacks = <String>[
  'lib/app/router.dart',
  'lib/features/video/presentation/pages/movie_player_page.dart',
  'lib/features/reader/presentation/pages/comic_reader_page.dart',
  'lib/features/reader/presentation/pages/reader_metadata_edit_page.dart',
  'lib/features/reader/presentation/widgets/reader_view_page_controls_mixin.dart',
];

Future<Map<String, int>> _scanModuleGo() async {
  final hits = <String, int>{};
  await for (final entity in Directory('lib').list(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    final path = entity.path.replaceAll('\\', '/');
    final count = _moduleGo.allMatches(await entity.readAsString()).length;
    if (count > 0) {
      hits[path] = count;
    }
  }
  return hits;
}

void main() {
  test('模块页入口不得用 go 替换整条栈', () async {
    final hits = await _scanModuleGo();
    final offenders = <String>[
      for (final entry in hits.entries)
        if (entry.value > (_baseline[entry.key] ?? 0))
          '${entry.key}: ${entry.value} > ${_baseline[entry.key] ?? 0}',
      for (final entry in _baseline.entries)
        if ((hits[entry.key] ?? 0) < entry.value)
          '${entry.key}: 已降到 ${hits[entry.key] ?? 0}，请同步收紧基线',
    ]..sort();

    expect(
      offenders,
      isEmpty,
      reason:
          '模块页入口必须 push（保留来路），go 会让系统返回直接退出应用：\n'
          '${offenders.join('\n')}',
    );
  });

  test('兜底 go 仍然被 canPop 保护', () async {
    for (final path in _guardedFallbacks) {
      final source = await File(path).readAsString();
      expect(
        source.contains('canPop'),
        isTrue,
        reason:
            '$path 的 go 只在栈底（深链直入）时兜底；'
            '没有 canPop 判断就意味着正常返回也换了栈',
      );
    }
  });
}
