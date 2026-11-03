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
/// 其余展示层调用点必须传 `l10n:`。基线取当前实测值，只降不升，和字号/时长/
/// 加载动画棘轮同一口径；降到 0 后应把常数改成 0 变成常驻硬闸门。
void main() {
  // 2026-11-03 实测：展示层未本地化且属用户可见路径的调用点 49 处；profile 组 4 处与 admin 组 8 处已补 l10n，基线降到 37。
  const unlocalizedDisplayCeiling = 37;

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
          final isLog =
              before.contains('devLog(') || restOfLine.contains('devLog(');
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
