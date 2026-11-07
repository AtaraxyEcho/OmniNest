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
/// 有 `BuildContext` 的展示层（`presentation/` 与 `core/`）必须传 `l10n:`；
/// 没有上下文的 `application/` 层必须改用 `userFacingErrorText` /
/// `userFacingErrorDisplayText`，它们按当前 UI 语言解析。两个集合都按 0 处
/// 违例收紧，新增一处违规就直接判失败。
void main() {
  const unlocalizedDisplayCeiling = 0;
  const directTextExtractionCeiling = 0;

  String normalize(String path) => path.replaceAll(r'\', '/');

  List<File> dartFiles(Iterable<String> pathMarkers) {
    return Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) {
          final path = normalize(f.path);
          if (path.contains('/app/l10n/') ||
              path.endsWith('core/errors/error_message.dart')) {
            return false;
          }
          return pathMarkers.any(path.contains);
        })
        .toList();
  }

  /// 有 BuildContext 的层：展示组件与 core 内嵌组件。
  List<File> contextAwareFiles() =>
      dartFiles(const ['/presentation/', '/core/']);

  /// 无 BuildContext 的控制器层。
  List<File> applicationFiles() => dartFiles(const ['/application/']);

  test('有上下文的展示层必须传 l10n，违例数只降不升', () {
    final offenders = <String>[];
    final marker = 'describeUserFacingError(';

    for (final file in contextAwareFiles()) {
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
          '展示层出现未本地化的用户可见错误（基线 $unlocalizedDisplayCeiling 处），'
          '英文用户会看到服务端中文。新增调用请传 l10n:，'
          '或改用签名强制传入本地化实例的 errorReason。\n'
          '${offenders.join('\n')}',
    );
  });

  test('控制器层取展示文案必须走 userFacingErrorText，违例数只降不升', () {
    final offenders = <String>[];
    final marker = 'describeUserFacingError(';
    // 直接取 message/displayMessage 会把服务端中文写进 state.errorMessage。
    final extraction = RegExp(r'^\s*\.(message|displayMessage)\b');

    for (final file in applicationFiles()) {
      final source = file.readAsStringSync();
      if (!source.contains(marker)) {
        continue;
      }
      for (var found = source.indexOf(marker);
          found >= 0;
          found = source.indexOf(marker, found + marker.length)) {
        final end = _matchingParen(source, found + marker.length - 1);
        final after = source.substring(
          end + 1,
          (end + 24).clamp(0, source.length),
        );
        if (extraction.hasMatch(after)) {
          final line = source.substring(0, found).split('\n').length;
          offenders.add('${normalize(file.path)}:$line');
        }
      }
    }

    expect(
      offenders.length,
      lessThanOrEqualTo(directTextExtractionCeiling),
      reason:
          '控制器层直接取 describeUserFacingError(...).message 会绕过 UI 语言，'
          '英文界面下仍显示中文。请改用 userFacingErrorText(error)，'
          '需要保留数字错误码后缀时用 userFacingErrorDisplayText(error)。\n'
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
