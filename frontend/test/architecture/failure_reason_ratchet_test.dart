import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 失败提示必须带得出原因：吞掉异常的 catch 只许存留，不许新增。
///
/// `[错误类型] catch` 没绑定异常就弹提示，用户只能看到"操作失败"，
/// 分不清是自己权限不够、任务还在重试，还是服务端 503——管理员只能反复
/// 点同一个按钮。已修掉的 admin 操作台八个站点就是这个形状。
///
/// 判定：`on Object {` / `on Exception {` / `catch (_)` 这类不绑定异常的头，
/// 若其函数体里出现用户可见提示，即为违例。存量按实测登记，只许降不许升。
void main() {
  // 2026-11-03 实测 36 处（admin 操作台本轮已清零）：相册 18、个人资料 5、
  // 通知 5、音乐 3、影视 3。批量动作与进度浮层里"操作失败"可能就是正确文案，
  // 需逐站判定后再收紧，因此这里登记为只降不升的存量上限。
  const unboundFailureCeiling = 36;

  const catchHeads = [
    '} on Object {',
    '} on Exception {',
    '} on Error {',
    '} catch (_)',
  ];
  const userVisibleMessages = [
    'showOmniFeedback(',
    'showMovieFeedback(',
    'showSnackBar',
  ];

  final offenders = <String>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    final path = entity.path.replaceAll('\\', '/');
    final lines = entity.readAsLinesSync();
    for (var index = 0; index < lines.length; index++) {
      final head = lines[index].trim();
      if (!catchHeads.any(head.startsWith)) {
        continue;
      }
      var depth = 0;
      var opened = false;
      var closed = false;
      final body = StringBuffer();
      for (var cursor = index; cursor < lines.length && !closed; cursor++) {
        final line = lines[cursor];
        body.writeln(line);
        // 头行的 `}` 属于上一个块，只从它之后开始数大括号：
        // 否则要么一进一出被当成空函数体，要么负深度让收口判据永不成立。
        final scanFrom = cursor == index ? line.indexOf('}') + 1 : 0;
        for (var i = scanFrom; i < line.length; i++) {
          final char = line[i];
          if (char == '{') {
            depth++;
            opened = true;
          } else if (char == '}') {
            depth--;
          }
          if (opened && depth == 0) {
            closed = true;
            break;
          }
        }
      }
      final text = body.toString();
      if (userVisibleMessages.any(text.contains)) {
        offenders.add('$path:${index + 1}');
      }
    }
  }

  test('不绑定异常就弹提示的 catch 不得新增', () {
    expect(
      offenders.length,
      lessThanOrEqualTo(unboundFailureCeiling),
      reason:
          '吞掉原因的失败提示从 $unboundFailureCeiling 涨到 ${offenders.length} 处：'
          '${offenders.join(', ')}；修掉一处请同时收紧上限',
    );
  });

  test('admin 操作台不得再有吞原因的失败提示', () {
    final adminOffenders =
        offenders.where((value) => value.contains('/features/admin/')).toList();
    expect(
      adminOffenders,
      isEmpty,
      reason: '管理台必须透传原因：${adminOffenders.join(', ')}',
    );
  });
}
