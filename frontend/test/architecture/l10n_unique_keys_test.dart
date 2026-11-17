import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ARB 里重复的键会被 `json.decode` 静默吞成「后者覆盖前者」：
/// 新增文案时若抄了已有键名，界面会突然换词，测试也可能只在别的模块红。
/// 这条守卫直接按文本扫键名，重复即失败。
void main() {
  test('ARB 键名唯一，模板之间键集合一致', () {
    final en = _keys('lib/app/l10n/app_en.arb');
    final zh = _keys('lib/app/l10n/app_zh.arb');

    expect(
      en.duplicates,
      isEmpty,
      reason: 'app_en.arb 重复键：${en.duplicates.join(', ')}',
    );
    expect(
      zh.duplicates,
      isEmpty,
      reason: 'app_zh.arb 重复键：${zh.duplicates.join(', ')}',
    );
    expect(
      zh.names.difference(en.names),
      isEmpty,
      reason: '中文模板多出的键',
    );
    expect(
      en.names.difference(zh.names),
      isEmpty,
      reason: '英文模板多出的键',
    );
  });
}

class _ArbKeys {
  _ArbKeys(this.names, this.duplicates);

  final Set<String> names;
  final List<String> duplicates;
}

_ArbKeys _keys(String path) {
  final text = File(path).readAsStringSync();
  // 顶层键固定两格缩进；嵌套的 placeholders/count 是四格，不参与比对。
  final pattern = RegExp(r'^  "([^"@][^"]*)"\s*:', multiLine: true);
  final seen = <String>{};
  final duplicates = <String>[];
  for (final match in pattern.allMatches(text)) {
    final name = match.group(1)!;
    if (!seen.add(name)) {
      duplicates.add(name);
    }
  }
  return _ArbKeys(seen, duplicates);
}
