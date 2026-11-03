import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 失败提示必须带得出原因：不绑定异常的 catch 只允许留下已登记的例外。
///
/// `catch` 头不接异常又弹提示，用户只能看到"操作失败"，分不清是自己权限不够、
/// 任务还在重试还是服务端 503——只能反复点同一个按钮。admin 操作台的八个站点
/// 就是这个形状，本轮已改为 `errorReason(error, l10n)` 组合既有动作文案。
///
/// 判定：`} on Object {` / `} on Exception {` / `} on Error {` / `} catch (_)`
/// 这类不绑定异常的头，若函数体里出现用户可见提示即为违例；违例集合必须与
/// 下面的登记完全一致——新增要写理由，修掉要删登记。
void main() {
  /// 逐站判定后保留的例外：文案本身已给出原因或处置方式。
  const allowedUnboundFailures = <String, String>{
    'lib/features/photos/presentation/pages/photo_detail_page.dart:245':
        '文案已点名"离线地名库缺失"这一原因，再拼一层无新增信息',
    'lib/features/photos/presentation/widgets/batch_progress_dialog.dart:64':
        '打包下载失败已给出"重新选择同一路径继续"的处置动作',
    // 音乐区由并行会话持有，本轮不越界改其文案。
    'lib/features/music/presentation/deck/music_deck_content_support.dart:738':
        '并行会话在途文件',
    'lib/features/music/presentation/player/music_mobile_now_playing.dart:457':
        '并行会话在途文件',
    'lib/features/music/presentation/widgets/music_mobile_mini_player_slot.dart:295':
        '并行会话在途文件',
  };

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

  test('不绑定异常就弹提示的 catch 必须逐站登记', () {
    final unregistered =
        offenders
            .where((value) => !allowedUnboundFailures.containsKey(value))
            .toList()
          ..sort();
    expect(
      unregistered,
      isEmpty,
      reason:
          '新增吞掉原因的失败提示：${unregistered.join(', ')}；'
          '请绑定异常并接 errorReason，或说明为何文案本身已够',
    );

    final stale =
        allowedUnboundFailures.keys
            .where((value) => !offenders.contains(value))
            .toList()
          ..sort();
    expect(
      stale,
      isEmpty,
      reason: '登记已失效，请从基线删除（改好了或行号已移动）：${stale.join(', ')}',
    );
  });
}
