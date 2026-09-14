import 'package:flutter/foundation.dart';

import 'package:omninest/features/reader/application/reading_runtime/reader_geometry_commit.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_geometry_invalidation.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_geometry_store.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_resolver.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_progress_projection.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_progress_publisher.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_restore_manager.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_clock.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_diagnostics.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_transaction_manager.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_visual_extent_table.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_window_manager.dart';

/// Reader Reading Runtime Facade（方案 §83）：页面只经此访问运行时。
///
/// 四个 Authority（Position / Geometry / Transaction / Progress）加上
/// Window 与 Restore 管理器在此聚合；[currentPosition] 是最近一次被
/// 接受的位置事实，供离场快照与诊断读取。
class ReaderReadingRuntime {
  ReaderReadingRuntime({
    ReaderTransactionManager? transactions,
    ReaderGeometryStore? geometry,
    ReaderPositionResolver? position,
    ReaderProgressProjection? progress,
    ReaderVisualProgressPublisher? publisher,
    ReaderWindowManager? window,
    ReaderRestoreManager? restore,
    ReaderRuntimeClock? clock,
    ReaderRuntimeDiagnostics? diagnostics,
    ReaderGeometryCommit? geometryCommit,
  }) : transactions = transactions ?? ReaderTransactionManager(),
       geometry = geometry ?? ReaderGeometryStore(),
       position = position ?? const ReaderPositionResolver(),
       progress = progress ?? ReaderProgressProjection(),
       publisher =
           publisher ?? ReaderVisualProgressPublisher(ValueNotifier<double>(0)),
       window = window ?? ReaderWindowManager(),
       restore = restore ?? ReaderRestoreManager(),
       clock = clock ?? const SystemReaderRuntimeClock(),
       diagnostics = diagnostics ?? ReaderRuntimeDiagnostics(),
       geometryCommit = geometryCommit ?? const ReaderGeometryCommit();

  final ReaderTransactionManager transactions;

  final ReaderGeometryStore geometry;

  final ReaderPositionResolver position;

  final ReaderProgressProjection progress;

  /// bookProgressNotifier 的唯一写者（方案 §50）。
  final ReaderVisualProgressPublisher publisher;

  final ReaderWindowManager window;

  final ReaderRestoreManager restore;

  final ReaderRuntimeClock clock;

  final ReaderRuntimeDiagnostics diagnostics;

  /// 结束性 Geometry Commit 与锚点保持修正（方案 §38/§94）。
  final ReaderGeometryCommit geometryCommit;

  ReaderPositionSnapshot? currentPosition;

  /// 全书视觉进度表（方案 §81 自 Widget 迁入；idle 显示与视觉 seek 用）。
  final ReaderVisualExtentTable visualExtent = ReaderVisualExtentTable();

  /// 收敛期守卫缓存（方案 §81）：上次解析的物理 offset 与章节身份。
  double? lastResolvedOffset;

  String? lastResolvedProgressChapterId;

  /// 几何失效回调（方案 §72）：页面在 initState 注入实际调度器；
  /// build / 事件只经 [requestGeometryUpdate] 声明失效，不同步提交。
  void Function(ReaderGeometryInvalidation reason)? onGeometryInvalidated;

  /// 几何失效请求唯一入口（方案 §72/§73）：请求与提交必须分离。
  void requestGeometryUpdate({required ReaderGeometryInvalidation reason}) {
    onGeometryInvalidated?.call(reason);
  }

  /// 释放 Facade 自建的通知器；页面自持通知器时通过自建 publisher 注入，
  /// 由页面负责其 dispose。
  void disposeOwnNotifier() {
    final notifier = publisher.notifier;
    notifier.dispose();
  }
}
