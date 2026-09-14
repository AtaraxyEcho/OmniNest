import 'package:flutter/foundation.dart' show immutable;

import 'package:omninest/features/reader/application/reading_runtime/reader_reading_runtime.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_diagnostics.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_continuous_scroll_controller.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_scroll_geometry_snapshot.dart';

/// 窗口章指纹采样行（B4）：锚点章与邻章的指纹相关字段投影。
@immutable
class ReaderWindowChapterSample {
  const ReaderWindowChapterSample({
    required this.chapterId,
    this.blockCount = 0,
    this.totalChars = 0,
    this.hasPreciseHeights = false,
    this.lastCumulativeHeight,
  });

  final String chapterId;
  final int blockCount;
  final int totalChars;
  final bool hasPreciseHeights;
  final double? lastCumulativeHeight;
}

/// 窗口指纹输入（B4）：纯值对象，计算与页面/加载器解耦。
@immutable
class ReaderWindowFingerprintInput {
  const ReaderWindowFingerprintInput({
    required this.anchorChapterId,
    required this.fontSize,
    required this.lineHeight,
    required this.fontFamily,
    required this.immersiveMode,
    required this.pageWidth,
    required this.textScale,
    required this.chapters,
  });

  final String anchorChapterId;
  final double fontSize;
  final double lineHeight;
  final String fontFamily;
  final bool immersiveMode;
  final double pageWidth;
  final double textScale;

  /// 锚点章在前、邻章随后的采样行序列。
  final List<ReaderWindowChapterSample> chapters;
}

/// 窗口状态指纹纯计算器（B4 自页面 _computeWindowFingerprint 迁入）：
/// 同一输入必得同一指纹；高度按 64px 桶量化，精测分批不触发整页 rebuild。
class ReaderWindowFingerprintCalculator {
  const ReaderWindowFingerprintCalculator._();

  static int compute(ReaderWindowFingerprintInput input) {
    var hash = Object.hash(
      input.anchorChapterId,
      input.fontSize,
      input.lineHeight,
      input.fontFamily,
      input.immersiveMode,
      input.pageWidth,
      input.textScale,
    );
    for (final sample in input.chapters) {
      // 不用 layoutVersion：精测分批会频繁 bump，导致每批整页 rebuild。
      final lastHeight = sample.lastCumulativeHeight;
      final heightBucket =
          lastHeight == null ? -1.0 : (lastHeight / 64).roundToDouble() * 64;
      hash = Object.hash(
        hash,
        sample.chapterId,
        sample.blockCount,
        sample.totalChars,
        sample.hasPreciseHeights,
        heightBucket,
      );
    }
    return hash;
  }
}

/// Window 构建页面供给接口（B4）：loader 采样、控制器操作与视口补偿
/// 的页面适配；构建编排与指纹状态归 Runtime 侧 [ReaderWindowBuilder]。
abstract interface class ReaderWindowBuildDelegate {
  bool get isPageMode;

  /// 构建数据是否就绪（loader 已初始化）。
  bool get hasBuildData;

  String get anchorChapterId;

  List<String> get chapterIds;

  /// 缓存半径内的邻章 id 列表（不含锚点）。
  List<String> neighborIdsOf(String anchorChapterId);

  /// 解析元数据字数（无元数据时为 null）。
  int? charCountOf(String chapterId);

  /// 章节指纹采样行（无数据时由构建器以默认行参与哈希）。
  ReaderWindowChapterSample? sampleChapter(String chapterId);

  double get pageWidth;
  double get textScale;
  double get fontSize;
  double get lineHeight;
  String get fontFamily;
  bool get immersiveMode;

  bool get scrollAttached;
  double get currentScrollOffset;
  double get viewportAnchorY;

  bool get windowEmpty;
  List<ContinuousChapterEntry> get entries;
  double prefixHeightOf(String chapterId);
  VisualAnchor? visualAnchorAt(double windowContentY);
  ReaderGeometrySnapshot buildGeometrySnapshot();

  /// 执行窗口控制器重建（estimate/resolve 由页面按当前排版闭合）。
  void rebuildWindow({
    required String anchorChapterId,
    required List<String> chapterIds,
    required double pageWidth,
  });

  /// 以锚点章为基准预取并准备邻章滚动布局。
  void ensureScrollLayoutForNeighbors(
    String anchorChapterId, {
    required double pageWidth,
    required double textScale,
  });

  /// 滑窗补偿（坐标原点平移类，即时执行）。
  void compensateWindowSlide({
    required List<ContinuousChapterEntry> prevEntries,
    required String? prevFirstId,
    required String? prevLastId,
    required double prevFirstHeight,
    required double prevLastHeight,
    required VisualAnchor? anchorBefore,
    required ReaderGeometrySnapshot geometryBefore,
    required double anchorContentY,
  });

  /// 前缀高度差补偿（高度收敛类）。
  void compensatePrefixDelta({
    required double? previousPrefix,
    required VisualAnchor? anchorBefore,
    required ReaderGeometrySnapshot geometryBefore,
    required double anchorContentY,
  });
}

/// Window 构建器（方案 §20/§21/§48）：指纹判定、锚点捕获、窗口重建与
/// Live 几何装载的 Runtime 侧编排；页面数据经 [ReaderWindowBuildDelegate]
/// 注入。Live 几何只在真实重建时装入 Store，读取路径一律只读。
class ReaderWindowBuilder {
  ReaderWindowBuilder(this._runtime);

  final ReaderReadingRuntime _runtime;

  /// 页面适配（initState 注入）。
  ReaderWindowBuildDelegate? delegate;

  int? _lastFingerprint;
  bool _building = false;

  // 滑窗检测状态：上次构建后的首尾章身份与高度。
  String? _firstChapterId;
  String? _lastChapterId;
  double _firstChapterHeight = 0;
  double _lastChapterHeight = 0;

  /// 使下次构建跳过指纹短路（扩窗/布局失效场景）。
  void invalidateFingerprint() {
    _lastFingerprint = null;
  }

  /// 执行一次窗口构建（B4 自页面 rebuildContinuousWindow 迁入）。
  ///
  /// 返回是否真实发生重建。提交边界由 GeometryScheduler 决定（B5 §49）：
  /// 手势期间（非终端）只登记挂起并整段跳过（§61：不 dispose/不重建任何
  /// 已挂载图片）；终端提交（settle 旁路）取最新状态一次装载；指纹未
  /// 变化且窗口非空时同样跳过。
  bool build({bool deferIfGestureActive = true}) {
    final d = delegate;
    if (d == null || _building || d.isPageMode || !d.hasBuildData) {
      return false;
    }
    if (!_runtime.geometryScheduler.authorizeInstall(
      inActiveGesture: _runtime.isInActiveGesture,
      terminal: !deferIfGestureActive,
    )) {
      // ACTIVE_SCROLL：窗口重建推迟到 ScrollEnd 一次提交（方案 §12），
      // 坐标系变化不得发生在用户滚动手势期间。
      _runtime.window.pendingMetricUpdate = true;
      return false;
    }
    _building = true;
    try {
      final pageWidth = d.pageWidth;
      final textScale = d.textScale;
      final fingerprint = ReaderWindowFingerprintCalculator.compute(
        ReaderWindowFingerprintInput(
          anchorChapterId: d.anchorChapterId,
          fontSize: d.fontSize,
          lineHeight: d.lineHeight,
          fontFamily: d.fontFamily,
          immersiveMode: d.immersiveMode,
          pageWidth: pageWidth,
          textScale: textScale,
          chapters: [
            for (final id in [
              d.anchorChapterId,
              ...d.neighborIdsOf(d.anchorChapterId),
            ])
              // 缺数据行仍以真实章节 id 参与哈希（与页面实现等价）。
              d.sampleChapter(id) ?? ReaderWindowChapterSample(chapterId: id),
          ],
        ),
      );
      if (_lastFingerprint == fingerprint && !d.windowEmpty) {
        return false;
      }
      _lastFingerprint = fingerprint;

      // 记录滑窗前首尾章，rebuild 后用高度差保持视口稳定。
      final prevFirstId = _firstChapterId;
      final prevLastId = _lastChapterId;
      final prevFirstHeight = _firstChapterHeight;
      final prevLastHeight = _lastChapterHeight;
      final prevEntries = d.entries;
      // 布局变化前捕获视觉锚点：变化后按同一锚点保持视口（P0-17），
      // 而非机械保持 offset 数值。
      final anchorBefore =
          d.scrollAttached
              ? d.visualAnchorAt(d.currentScrollOffset + d.viewportAnchorY)
              : null;
      // 旧几何快照：Geometry Commit 的 old 侧输入（方案 §38/§70）。
      final geometryBefore = d.buildGeometrySnapshot();
      // 锚点在旧布局中的窗口内容坐标：应用期按"新布局位置 - 旧布局
      // 位置"的位移修正当前 offset，与用户滚动自然叠加，不再回拉。
      final anchorContentY =
          anchorBefore == null
              ? 0.0
              : d.currentScrollOffset + d.viewportAnchorY;

      d.ensureScrollLayoutForNeighbors(
        d.anchorChapterId,
        pageWidth: pageWidth,
        textScale: textScale,
      );
      final previousPrefix =
          d.windowEmpty ? null : d.prefixHeightOf(d.anchorChapterId);
      d.rebuildWindow(
        anchorChapterId: d.anchorChapterId,
        chapterIds: d.chapterIds,
        pageWidth: pageWidth,
      );

      final nextEntries = d.entries;
      if (nextEntries.isNotEmpty) {
        _firstChapterId = nextEntries.first.chapterId;
        _lastChapterId = nextEntries.last.chapterId;
        _firstChapterHeight = nextEntries.first.totalHeight;
        _lastChapterHeight = nextEntries.last.totalHeight;
      }

      final windowSlid =
          prevFirstId != null &&
          (nextEntries.isEmpty ||
              nextEntries.first.chapterId != prevFirstId ||
              (prevLastId != null && nextEntries.last.chapterId != prevLastId));
      if (windowSlid) {
        d.compensateWindowSlide(
          prevEntries: prevEntries,
          prevFirstId: prevFirstId,
          prevLastId: prevLastId,
          prevFirstHeight: prevFirstHeight,
          prevLastHeight: prevLastHeight,
          anchorBefore: anchorBefore,
          geometryBefore: geometryBefore,
          anchorContentY: anchorContentY,
        );
      }
      // GeometryStore 接入（方案 §13/§42/§94）：builder 输出即 Candidate，
      // 装载边界已经调度器放行，此处提交为 Live 并登记结束性 Commit。
      final live = d.buildGeometrySnapshot();
      _runtime.geometry.publishCandidate(live);
      _runtime.geometry.commitCandidate();
      _runtime.diagnostics.geometryCommitCount++;
      _runtime.emitEvent(
        ReaderRuntimeEvent(
          type: ReaderRuntimeEventType.geometryCommitted,
          at: _runtime.clock.now,
          transactionId: _runtime.transactions.current?.id ?? 0,
          layoutRevision: '${live.revision}',
        ),
      );

      // 滑窗已按首尾高度补偿，勿再按锚点 prefix 二次修正。
      if (!windowSlid) {
        d.compensatePrefixDelta(
          previousPrefix: previousPrefix,
          anchorBefore: anchorBefore,
          geometryBefore: geometryBefore,
          anchorContentY: anchorContentY,
        );
      }
      return true;
    } finally {
      _building = false;
    }
  }
}
