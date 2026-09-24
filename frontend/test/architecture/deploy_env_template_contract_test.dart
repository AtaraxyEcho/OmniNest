import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 部署模板与 Compose 的契约：compose 引用的每个变量都必须在同目录的中英文
/// 模板里出现（注释掉的可选形式也算已记录），且两份模板键集合一致。
const _templatesByDirectory = <String, List<String>>{
  '../deploy/prod': [
    '../deploy/prod/docker-compose.yml',
    '../deploy/prod/docker-compose.single.yml',
  ],
  '../deploy/dev': ['../deploy/dev/docker-compose.yml'],
};

/// Compose 自身消费的变量，不属于 .env 契约。
const _notEnvVariables = <String>{'COMPOSE_PROFILES'};

final _referencePattern = RegExp(r'(?<!\$)\$\{([A-Z][A-Z0-9_]*)(:?-[^}]*)?\}');
final _assignmentPattern = RegExp(r'^\s*#?\s*([A-Z][A-Z0-9_]*)=');
// 注释掉的 `# KEY=` 只是可选示例，算已登记但不算第二次声明，否则同一个键的
// 多段用法说明会被误判为重复声明。
final _declaredPattern = RegExp(r'^([A-Z][A-Z0-9_]*)=');

List<String> _lines(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    fail('缺少文件：$path');
  }
  return file.readAsLinesSync();
}

Set<String> _documentedKeys(String templatePath) {
  return _lines(templatePath)
      .map((line) => _assignmentPattern.firstMatch(line)?.group(1))
      .whereType<String>()
      .toSet();
}

Set<String> _referencedVariables(Iterable<String> composePaths) {
  return composePaths
      .map((path) => _lines(path).join('\n'))
      .expand(
        (text) => _referencePattern
            .allMatches(text)
            .map((match) => match.group(1)!)
            .where((name) => !_notEnvVariables.contains(name)),
      )
      .toSet();
}

List<String> _assignmentNames(String templatePath) {
  final lines = _lines(templatePath);
  return lines
      .map((line) => _declaredPattern.firstMatch(line)?.group(1))
      .whereType<String>()
      .toList();
}

void main() {
  group('deploy env 模板契约', () {
    for (final entry in _templatesByDirectory.entries) {
      final directory = entry.key;

      test('${_basename(directory)}：compose 引用的变量都要在模板中登记', () {
        final referenced = _referencedVariables(entry.value);
        for (final suffix in ['.env.example', '.env.en.example']) {
          final missing =
              referenced
                  .difference(_documentedKeys('$directory/$suffix'))
                  .toList()
                ..sort();
          expect(missing, isEmpty, reason: '$directory/$suffix 缺少的变量');
        }
      });

      test('${_basename(directory)}：中英文模板键集合一致', () {
        final zh = _documentedKeys('$directory/.env.example');
        final en = _documentedKeys('$directory/.env.en.example');
        expect(en.difference(zh), isEmpty, reason: '$directory 仅英文版有的键');
        expect(zh.difference(en), isEmpty, reason: '$directory 仅中文版有的键');
      });

      test('${_basename(directory)}：模板不重复声明同一个键', () {
        for (final suffix in ['.env.example', '.env.en.example']) {
          final names = _assignmentNames('$directory/$suffix');
          final duplicated =
              names
                  .toSet()
                  .where(
                    (name) => names.where((other) => other == name).length > 1,
                  )
                  .toList()
                ..sort();
          expect(duplicated, isEmpty, reason: '$directory/$suffix 重复声明');
        }
      });
    }
  });
}

String _basename(String path) => path.split('/').last;
