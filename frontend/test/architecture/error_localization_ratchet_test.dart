import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 用户可见错误文案的本地化棘轮（FUNC-M06b）。
///
/// `describeUserFacingError` 是两段式设计：不传 `l10n` 时返回服务端原文加稳定
/// `code`，由展示层再映射。展示层若既没传 `l10n`、又没走 `localizeUserFacing`，
/// 英文用户就会看到服务端的中文文案。
///
/// 三类用法**不算**违例，因为它们的结果不直接成为展示文本：
/// 1. 写进 `devLog(...)` 的日志；
/// 2. 取 `.code` 做分支的稳定错误码；
/// 3. 已交给 `localizeUserFacing(...)` 按 code 再映射的。
///
/// 其余展示层调用点必须传 `l10n:`。基线从 2026-11-03 实测的 49 处降到 4，
/// 余下 4 处受文件大小棘轮阻塞，随文件拆分清零；在那之前任何新增不传 `l10n:`
/// 的展示层调用都会直接判失败。
void main() {
  // 2026-11-03 实测起点 49 处，已补全 48 处（profile 4、admin 8、photos 12、music 9、reader 8、files 2、portal 1、video 2）。
  // 剩 1 处卡在文件大小棘轮上：initial_setup_page 的 116 行——任何补法都会让该已登记
  // 长文件超过基线，因此与它的职责拆分同批做（见 FUNC-L03），拆完立刻归零。
  const unlocalizedDisplayCeiling = 1;

  String normalize(String path) => path.replaceAll(r'\', '/');

  List<File> presentationFiles() {
    return Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              f.path.endsWith('.dart') &&
              normalize(f.path).contains('/presentation/'),
        )
        .toList();
  }

  test('展示层用户可见错误必须本地化，违例数只降不升', () {
    final offenders = <String>[];
    final marker = 'describeUserFacingError(';

    for (final file in presentationFiles()) {
      final source = file.readAsStringSync();
      if (!source.contains(marker)) {
        continue;
      }
      final lines = source.split('\n');
      var offset = 0;
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        var searchFrom = 0;
        while (true) {
          final found = line.indexOf(marker, searchFrom);
          if (found < 0) {
            break;
          }
          final absolute = offset + found;
          final end = _matchingParen(source, absolute + marker.length - 1);
          final call = source.substring(absolute, end + 1);
          final after = source.substring(
            end + 1,
            (end + 12).clamp(0, source.length),
          );
          final ahead = source.substring(
            end + 1,
            (end + 200).clamp(0, source.length),
          );
          final before = source.substring(
            (absolute - 60).clamp(0, source.length),
            absolute,
          );
          final restOfLine = source.substring(
            absolute,
            source.indexOf('\n', absolute) < 0
                ? source.length
                : source.indexOf('\n', absolute),
          );
          final passesL10n = call.contains('l10n:');
          // 日志用法有两种写法：devLog(describeUserFacingError(...)) 与
          // 先取 message 再交给 devLog。后者在调用点之后，所以必须前看。
          final isLog =
              before.contains('devLog(') ||
              restOfLine.contains('devLog(') ||
              ahead.contains('devLog(');
          final isStableCode = after.trimLeft().startsWith('.code');
          final isRemapped = before.contains('localizeUserFacing(');
          if (!passesL10n && !isLog && !isStableCode && !isRemapped) {
            offenders.add('${normalize(file.path)}:${index + 1}');
          }
          searchFrom = found + marker.length;
        }
        offset += line.length + 1;
      }
    }

    expect(
      offenders.length,
      lessThanOrEqualTo(unlocalizedDisplayCeiling),
      reason:
          '展示层未本地化的用户可见错误从 $unlocalizedDisplayCeiling 处上升了，'
          '英文用户会看到服务端中文。新增请传 l10n:，修完一处就下调基线。\n'
          '${offenders.join('\n')}',
    );
  });
}

/// 返回与 [openIndex] 处左括号配对的右括号下标。
int _matchingParen(String source, int openIndex) {
  var depth = 0;
  for (var i = openIndex; i < source.length; i++) {
    if (source[i] == '(') {
      depth++;
    } else if (source[i] == ')') {
      depth--;
      if (depth == 0) {
        return i;
      }
    }
  }
  return source.length - 1;
}
