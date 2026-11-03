import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 部署模板与 Compose 的契约：compose 引用的每个变量都必须在同目录的中英文
/// 模板里出现（注释掉的可选形式也算已记录），且两份模板键集合一致。
///
/// 同一文件还承担子路径部署（`OMNINEST_WEB_BASE_HREF=/omninest/`）的契约：
/// Nginx 模板的变量必须全部在 `render-config.sh` 的 envsubst 白名单内，API 与
/// WebSocket 入口必须带 `${OMNINEST_WEB_BASE_PATH}` 前缀，且客户端的相对资源地址
/// 必须统一交给 `api_url_resolver` 解析——任一侧丢前缀都会让播放、字幕与封面 404。
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

/// Nginx 配置模板与渲染脚本：子路径前缀变量由 envsubst 注入。
const _nginxDirectory = '../deploy/prod/nginx';
const _nginxRenderScript = '$_nginxDirectory/render-config.sh';
const _nginxTemplates = <String>[
  '$_nginxDirectory/templates/http.conf.template',
  '$_nginxDirectory/templates/https.conf.template',
];
const _webBasePathVariable = 'OMNINEST_WEB_BASE_PATH';
const _webBasePathToken = r'${OMNINEST_WEB_BASE_PATH}';

/// 模板里 `${UPPER_CASE}` 形态的注入变量；nginx 自身的 `$scheme` 等不在其列。
final _bracedVariablePattern = RegExp(r'\$\{([A-Z][A-Z0-9_]*)\}');

/// envsubst 的白名单是被单引号包住的一个参数，只替换列出的变量。
final _envsubstWhitelistPattern = RegExp(r"envsubst\s+'([^']*)'");

/// location 指令，允许 `=`、`^~`、`~`、`~*` 修饰符。
final _locationPattern = RegExp(
  r'^location\s+(?:[=~]\*?\s+|\^~\s+|=\s+)?(\S+)',
);
final _apiEntryPattern = RegExp(r'(?:^|/)api(?:/|$)');
final _wsEntryPattern = RegExp(r'(?:^|/)ws(?:/|$)');

/// 后端下发相对资源地址、必须交给解析器换算的客户端解析点。
const _clientResolutionCallSites = <String>[
  'lib/features/video/data/movie_api.dart',
  'lib/features/video/data/movie_playback_repository_impl.dart',
  'lib/features/music/data/music_api.dart',
  'lib/features/music/data/music_cover_cache.dart',
];
const _apiUrlResolverImport =
    "import 'package:omninest/core/network/api_url_resolver.dart';";

/// 解析调用必须显式带上 Dio 的 baseUrl，否则拿不到子路径前缀。
final _resolveWithBaseUrlPattern = RegExp(
  r'resolveServerApiUrl\([^)]*options\.baseUrl',
);

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

Set<String> _bracedVariables(Iterable<String> lines) {
  return _bracedVariablePattern
      .allMatches(lines.join('\n'))
      .map((match) => match.group(1)!)
      .toSet();
}

/// 从渲染脚本读取 envsubst 白名单，避免在本测试里复制一份变量列表。
Set<String> _envsubstWhitelist() {
  final match = _envsubstWhitelistPattern.firstMatch(
    _lines(_nginxRenderScript).join('\n'),
  );
  if (match == null) {
    fail('$_nginxRenderScript 未声明 envsubst 变量白名单');
  }
  return match
      .group(1)!
      .split(RegExp(r'\s+'))
      .map((token) => token.replaceAll(RegExp(r'[${}]'), ''))
      .where((name) => name.isNotEmpty)
      .toSet();
}

/// 取出 location 指令的路径参数；注释行里出现的 “location” 不算指令。
List<String> _locationPaths(Iterable<String> lines) {
  return lines
      .map((line) => line.trimLeft())
      .where((line) => !line.startsWith('#'))
      .map((line) => _locationPattern.firstMatch(line)?.group(1))
      .whereType<String>()
      .toList();
}

/// 判定路径是否指向 API 或 WebSocket 入口，模板原文与渲染结果都适用。
bool _isApiOrWebSocketPath(String path) {
  final normalized = path.replaceAll(_webBasePathToken, '');
  return _apiEntryPattern.hasMatch(normalized) ||
      _wsEntryPattern.hasMatch(normalized);
}

/// 按 envsubst 的纯文本替换语义渲染模板，仅用于校验渲染结果。
List<String> _renderLines(Iterable<String> lines, String webBasePath) {
  return lines
      .map((line) => line.replaceAll(_webBasePathToken, webBasePath))
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

  group('子路径部署契约', () {
    test('envsubst 白名单必须放行子路径前缀变量', () {
      expect(_envsubstWhitelist(), contains(_webBasePathVariable));
    });

    test('nginx 模板引用的变量都在 envsubst 白名单内', () {
      final whitelist = _envsubstWhitelist();
      for (final template in _nginxTemplates) {
        // 白名单外的 `${VAR}` 不会被替换，会原样留在渲染出的配置里。
        final missing =
            _bracedVariables(_lines(template)).difference(whitelist).toList()
              ..sort();
        expect(
          missing,
          isEmpty,
          reason: '$_nginxRenderScript 的 envsubst 白名单缺少 ${missing.join(', ')}',
        );
      }
    });

    test('API 与 WebSocket location 必须带子路径前缀变量', () {
      for (final template in _nginxTemplates) {
        final lines = _lines(template);
        final text = lines.join('\n');
        // FUNC-H01 回归：裸 `/api/`、`/ws` 在子路径部署下匹配不到任何请求。
        expect(text, isNot(contains('location ^~ /api/')));
        expect(text, isNot(contains('location ^~ /ws')));

        final entries =
            _locationPaths(lines).where(_isApiOrWebSocketPath).toList();
        expect(
          entries.where((entry) => entry.contains('api')),
          isNotEmpty,
          reason: '$template 缺少 API 入口 location',
        );
        expect(
          entries.where((entry) => entry.contains('ws')),
          isNotEmpty,
          reason: '$template 缺少 WebSocket 入口 location',
        );

        final unprefixed =
            entries
                .where((entry) => !entry.startsWith(_webBasePathToken))
                .toList()
              ..sort();
        expect(
          unprefixed,
          isEmpty,
          reason:
              '$template 的代理入口未使用 \$_webBasePathVariable 前缀：'
              '${unprefixed.join(', ')}',
        );
      }
    });

    test('根部署渲染后代理入口回到 /api/ 与 /ws', () {
      for (final template in _nginxTemplates) {
        final rendered = _renderLines(_lines(template), '/');
        final entries =
            _locationPaths(rendered).where(_isApiOrWebSocketPath).toList()
              ..sort();
        expect(entries, containsAll(<String>['/api/', '/ws']));
        final notAbsolute =
            entries.where((entry) => !entry.startsWith('/')).toList();
        expect(notAbsolute, isEmpty, reason: '$template 渲染出相对入口：$notAbsolute');
        final doubled =
            entries.where((entry) => entry.startsWith('//')).toList();
        expect(doubled, isEmpty, reason: '$template 渲染出双斜杠入口：$doubled');

        final text = rendered.join('\n');
        expect(text, contains(r'rewrite ^/(api/.*)$ /$1 break;'));
        expect(text, contains(r'rewrite ^/(ws.*)$ /$1 break;'));
      }
    });

    test('子路径部署渲染后代理入口与 rewrite 同前缀', () {
      for (final template in _nginxTemplates) {
        final rendered = _renderLines(_lines(template), '/omninest/');
        final entries =
            _locationPaths(rendered).where(_isApiOrWebSocketPath).toList()
              ..sort();
        expect(
          entries,
          containsAll(<String>['/omninest/api/', '/omninest/ws']),
        );
        expect(entries, everyElement(startsWith('/omninest/')));

        final text = rendered.join('\n');
        expect(text, contains(r'rewrite ^/omninest/(api/.*)$ /$1 break;'));
        expect(text, contains(r'rewrite ^/omninest/(ws.*)$ /$1 break;'));
      }
    });

    test('客户端相对资源地址必须委派给 api_url_resolver', () {
      final violations = <String>[];
      for (final path in _clientResolutionCallSites) {
        final source = _lines(path).join('\n');
        if (!source.contains(_apiUrlResolverImport)) {
          violations.add('$path 未导入 api_url_resolver');
        }
        if (!_resolveWithBaseUrlPattern.hasMatch(source)) {
          violations.add('$path 未按 Dio baseUrl 调用 resolveServerApiUrl');
        }
        if (source.contains('.origin')) {
          violations.add('$path 用 origin 拼接绝对地址，会丢子路径前缀');
        }
      }
      expect(
        violations,
        isEmpty,
        reason: '子路径部署下资源地址会丢前缀并 404：\n${violations.join('\n')}',
      );
    });
  });
}

String _basename(String path) => path.split('/').last;
