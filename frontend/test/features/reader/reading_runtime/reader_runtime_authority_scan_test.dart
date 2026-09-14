import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Reader Runtime 权限扫描（B10 终验收：方案 §55/§56/§57/§58）。
///
/// 以源码静态断言固化三条纪律，回潮即红：
/// 1. §55 归零清单——已退役符号在 lib/test 全域零残留；
/// 2. §56 能力写路径唯一——四 Authority 的写 API 只出现在权威文件；
/// 3. §57 页面纯净——presentation 不触碰任何 Manager 内部（§63）。
///
/// 匹配前剥除行内 `//` 注释，历史文档性注释不构成回潮。
void main() {
  final packageRoot = Directory.current.path;
  final readerLib = Directory('$packageRoot/lib/features/reader');
  final readerTest = Directory('$packageRoot/test/features/reader');

  test('扫描环境就绪（package 根定位）', () {
    expect(
      readerLib.existsSync(),
      isTrue,
      reason: '须从 frontend/ 包根运行 flutter test',
    );
    expect(readerTest.existsSync(), isTrue);
  });

  /// 行级代码文本（剥除 `//` 注释段）。
  String codePart(String line) {
    final idx = line.indexOf('//');
    return idx < 0 ? line : line.substring(0, idx);
  }

  /// 收集 dart 源码为 (相对路径, 代码行) 列表；目录不存在即 fail
  /// （防腐断言禁止 fail-open 假绿）。
  List<(String, String)> collect(Directory dir, {required bool strip}) {
    expect(
      dir.existsSync(),
      isTrue,
      reason: '扫描目录不存在（须从 frontend/ 包根运行）：${dir.path}',
    );
    final rootPrefix = '${Directory.current.path.replaceAll('\\', '/')}/';
    final result = <(String, String)>[];
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final normalized = entity.path.replaceAll('\\', '/');
      final rel = normalized.startsWith(rootPrefix)
          ? normalized.substring(rootPrefix.length)
          : normalized;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final loc = '$rel:${i + 1}';
        result.add((loc, strip ? codePart(lines[i]) : lines[i]));
      }
    }
    return result;
  }

  /// §55 归零清单：符号 → 命中即失败。
  const retiredSymbols = <String>[
    'ScrollRestore',
    'ReaderRestoreTransaction',
    'ReaderPositionTracker',
    'ReaderScrollSession',
    'ContinuousScrollPosition',
    'ReaderModeSwitchPhase',
    'pendingMetricUpdate',
    'restoreSilenceUntil',
    'isRestoringProgress',
    'pendingRestoreCharOffset',
    'pendingChapterProgress',
    'beginRuntimeRestore',
    'isCallbackValid',
    'shouldSuppressWrites',
    '_scheduleBookProgressRecompute',
    '_scrollProgressNotifier',
    '_bookProgressRecomputeTimer',
    'onScrollPhaseChanged',
    'isScrollPhaseActive',
    'commitPendingContinuousMetrics',
    'rebuildContinuousWindow',
    'invalidateContinuousWindowFingerprint',
    'handleResolvedPosition',
    'visualProgressDuringScroll',
    'restoreToChapterStart',
    'ReaderGeometryCommitResult',
    'ReaderTransactionKind.visualSeek',
    'ReaderTransactionKind.restore',
    'ReaderPersistenceQueue',
    'persistenceQueue',
    'ReaderTargetResolver',
    // WindowManager 第二份收养状态的唯一写入口；tx.pendingChapterId
    // 是合法活代码，不能按符号全域禁用。
    'requestChapter',
    'disposeOwnNotifier',
  ];

  test('§55 归零清单：退役符号全域零残留', () {
    // §41 豁免：comic 模式独立滚动体系（同名概念属漫画自有实现）。
    // 扫描器自身豁免（清单声明即符号字面量）。
    final self = 'reader_runtime_authority_scan_test.dart';
    final all = [
      ...collect(
        readerLib,
        strip: true,
      ).where(((String, String) e) => !e.$1.contains('comic')),
      ...collect(readerTest, strip: true).where(
        ((String, String) e) => !e.$1.contains(self) && !e.$1.startsWith(self),
      ),
    ];
    final offenders = <String>[];
    for (final (loc, line) in all) {
      for (final symbol in retiredSymbols) {
        if (line.contains(symbol)) {
          offenders.add('$symbol @ $loc');
        }
      }
    }
    expect(offenders, isEmpty, reason: '退役符号回潮：\n${offenders.join('\n')}');
  });

  /// §56 能力写路径归属唯一：写 API → 允许文件（reader 包内相对路径）。
  final writePathRules = <(RegExp, Set<String>)>[
    // Progress Authority：全书进度发布唯一写者（§50）。
    (RegExp(r'\.publisher\.publish\('), {'reader_reading_runtime.dart'}),
    // Position Authority：物理位置双槽写口。
    (
      RegExp(r'\.acceptTransient\(|\.commitTransient\('),
      {'reader_reading_runtime.dart', 'reader_position_state.dart'},
    ),
    // 逻辑位置记账写口（B8）。
    (RegExp(r'logicalPosition\.accept\('), {'reader_reading_runtime.dart'}),
    // Transaction Authority：事务生命周期。
    (
      RegExp(r'\.transactions\.beginOrReplace\(|\.transactions\.finish\('),
      {'reader_reading_runtime.dart'},
    ),
    // Restore 相位写口（B6 相位机）。
    (
      RegExp(
        r'restore\.begin\(|restore\.markStabilizing\(|restore\.markCompleted\(|restore\.markTimedOut\(|restore\.markFailed\(|restore\.cancel\(',
      ),
      {'reader_reading_runtime.dart'},
    ),
    // Mode Switch 相位写口（B7 请求化）。
    (
      RegExp(r'modeSwitch\.begin\(|modeSwitch\.complete\('),
      {'reader_reading_runtime.dart'},
    ),
    // Geometry Authority：Candidate 提交与 Live 装载。
    (
      RegExp(r'installLive\(|commitCandidate\(|publishCandidate\('),
      {
        'reader_window_builder.dart',
        'reader_geometry_scheduler.dart',
        'reader_geometry_store.dart',
      },
    ),
  ];

  test('§56 能力扫描：四 Authority 写路径归属唯一', () {
    final all = collect(readerLib, strip: true);
    final offenders = <String>[];
    for (final (loc, line) in all) {
      final file = loc.split(':').first;
      for (final (pattern, allowed) in writePathRules) {
        if (pattern.hasMatch(line) && !allowed.any(file.endsWith)) {
          offenders.add('$pattern @ $loc');
        }
      }
    }
    expect(offenders, isEmpty, reason: '写路径越权：\n${offenders.join('\n')}');
  });

  test('§57 页面纯净：presentation 不触碰 Manager 内部（§63）', () {
    final presentation = Directory(
      '$packageRoot/lib/features/reader/presentation',
    );
    final all =
        collect(
          presentation,
          strip: true,
        ).where(((String, String) e) => !e.$1.contains('comic')).toList();
    final forbidden = <RegExp>[
      RegExp(r'_?runtime\.restore\.'),
      RegExp(r'_?runtime\.publisher\.'),
      RegExp(r'_?runtime\.transactions\.'),
      RegExp(r'_?runtime\.positionState\.'),
      RegExp(r'_?runtime\.geometry\.'),
      RegExp(r'_?runtime\.geometryScheduler\.'),
      RegExp(r'_?runtime\.geometryCommit\.'),
      RegExp(r'_?runtime\.modeSwitch\.'),
      RegExp(r'_?runtime\.window\.'),
      RegExp(r'_?runtime\.diagnostics\.'),
      RegExp(r'_?runtime\.eventLog\.'),
      RegExp(r'_?runtime\.operationToken\.'),
    ];
    final offenders = <String>[];
    for (final (loc, line) in all) {
      for (final pattern in forbidden) {
        if (pattern.hasMatch(line)) {
          offenders.add('$pattern @ $loc');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '页面越权访问 Manager：\n${offenders.join('\n')}',
    );
  });

  test('§58 新旧并存禁令：旧发射入口与新编排入口不并存', () {
    // 旧 ScrollRestore.start 与页模式恢复 start 入口零残留（§55 承载
    // 符号名；此处核验调用形态），restore 相位只能经 Facade 入口驱动。
    final all =
        collect(
          readerLib,
          strip: true,
        ).where(((String, String) e) => !e.$1.contains('comic')).toList();
    final offenders = <String>[];
    for (final (loc, line) in all) {
      if (line.contains('restore.start(')) {
        offenders.add(loc);
      }
    }
    expect(offenders, isEmpty, reason: '并存禁令违例');
  });
}
