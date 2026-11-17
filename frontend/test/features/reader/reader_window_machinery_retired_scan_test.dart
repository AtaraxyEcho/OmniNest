import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 窗口机器归零扫描门（引擎回滚移植防回潮）。
///
/// 多章无缝滚动窗口机制（92d7c36 引入，2a9f60f 剔除）的标志性符号
/// 一经回归即红；豁免本扫描器自身与纯注释行。
void main() {
  final repoRoot = _locatePackageRoot();
  final readerLib = Directory('$repoRoot/lib/features/reader');
  final scanSelf = File.fromUri(Platform.script).path;

  final retiredSymbols = <String, RegExp>{
    'reading_runtime 目录': RegExp(r'reading_runtime/'),
    'ReaderReadingRuntime': RegExp(r'\bReaderReadingRuntime\b'),
    'ReaderContinuousScrollController': RegExp(
      r'\bReaderContinuousScrollController\b',
    ),
    'ReaderContinuousScrollView': RegExp(r'\bReaderContinuousScrollView\b'),
    'ReaderContinuousPositionResolver': RegExp(
      r'\bReaderContinuousPositionResolver\b',
    ),
    'ReaderContinuousVisualMetrics': RegExp(
      r'\bReaderContinuousVisualMetrics\b',
    ),
    'ReaderScrollGeometrySnapshot': RegExp(r'\bReaderScrollGeometrySnapshot\b'),
    'ReaderPageFlow': RegExp(r'\bReaderPageFlow\b'),
    'ReaderProgressEcho': RegExp(r'\bReaderProgressEcho\b'),
    'ReaderNavigationToken': RegExp(r'\bReaderNavigationToken\b'),
    'ReaderWindowBuilder': RegExp(r'\bReaderWindowBuilder\b'),
    'adoptContinuousAnchorChapter': RegExp(r'\badoptContinuousAnchorChapter\b'),
    'onContinuousWindowExpand': RegExp(r'\bonContinuousWindowExpand\b'),
    'rebuildContinuousWindow': RegExp(r'\brebuildContinuousWindow\b'),
    'ensureScrollLayoutForNeighbors': RegExp(
      r'\bensureScrollLayoutForNeighbors\b',
    ),
    'dropHtmlForNeighbors': RegExp(r'\bdropHtmlForNeighbors\b'),
    'requestWindowCommit': RegExp(r'\brequestWindowCommit\b'),
    'windowContentYToCharOffset': RegExp(r'\bwindowContentYToCharOffset\b'),
  };

  test('无缝多章窗口机制退役符号全域零残留', () {
    expect(readerLib.existsSync(), isTrue);
    final violations = <String>[];
    for (final entity in readerLib.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      if (scanSelf.isNotEmpty && entity.path == scanSelf) {
        continue;
      }
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final codeOnly = lines[i].split('//').first;
        for (final entry in retiredSymbols.entries) {
          if (entry.value.hasMatch(codeOnly)) {
            violations.add(
              '${entity.path}:${i + 1} ${entry.key}（${lines[i].trim()}）',
            );
          }
        }
      }
    }
    expect(violations, isEmpty);
  });
}

/// 定位 package 根（frontend/），兼容从仓库根或 package 根运行。
String _locatePackageRoot() {
  var dir = Directory.current.path;
  if (File('$dir/pubspec.yaml').existsSync()) {
    return dir;
  }
  final candidate = '$dir/frontend';
  if (File('$candidate/pubspec.yaml').existsSync()) {
    return candidate;
  }
  fail('未定位到 pubspec.yaml（当前目录: $dir）');
}
