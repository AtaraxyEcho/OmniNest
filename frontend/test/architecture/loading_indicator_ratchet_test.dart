import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 加载动画门禁（M10）。
///
/// 项目规则是「一屏至多一处**加载**动画」，骨架块必须静态。这条规则此前只写在
/// 约定里、没有任何判据，所以新增转圈没人拦。这里钉两条：
///
/// 1. 同一个文件不得同时出现整屏 `AppLoading()` 与区级 `MobileLoadingLine`——
///    这两类一旦同屏就是两处加载动画。2026-10-14 实测违例为 0，所以这条是
///    常驻闸门而不是存量登记。
/// 2. `CircularProgressIndicator` 总数只降不升。基线取实测值，新增必须走
///    "接完一个面就把常数降到新值"的棘轮口径，和字号/时长棘轮同一形态。
///
/// 分档说明：整屏档 `AppLoading()` 34 处、区级档 `MobileLoadingLine` 5 文件、
/// 内联档 `CircularProgressIndicator` 124 处。只有前两档计入"每屏一处"约束——
/// 按钮内联 spinner 与沉浸浮层的进度环属内容节奏，不是页面级反馈，不在此列。
void main() {
  const inlineSpinnerCeiling = 124;

  List<File> dartFiles() {
    return Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
  }

  test('同一文件不得同时使用整屏与区级加载动画', () {
    final offenders = <String>[];
    for (final file in dartFiles()) {
      final source = file.readAsStringSync();
      if (source.contains('AppLoading()') &&
          source.contains('MobileLoadingLine')) {
        offenders.add(file.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          '一屏至多一处加载动画，以下文件同时挂了整屏与区级两种：'
          '\n${offenders.join('\n')}',
    );
  });

  test('内联转圈总数不再增长', () {
    var total = 0;
    for (final file in dartFiles()) {
      total +=
          'CircularProgressIndicator'
              .allMatches(file.readAsStringSync())
              .length;
    }
    expect(
      total,
      lessThanOrEqualTo(inlineSpinnerCeiling),
      reason:
          '当前 $total 处。接完一个面请把基线降到新值；'
          '要新增内联转圈，先确认它不是页面级反馈（页面级走 MobileLoadingLine，'
          '且同屏不得有第二处）。',
    );
  });
}
