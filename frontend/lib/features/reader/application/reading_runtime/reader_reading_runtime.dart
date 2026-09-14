import 'package:flutter/foundation.dart';

import 'package:omninest/features/reader/application/reading_runtime/reader_geometry_store.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_resolver.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_progress_projection.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_progress_publisher.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_restore_manager.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_clock.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_diagnostics.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_transaction_manager.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_window_manager.dart';
import 'package:omninest/features/reader/presentation/widgets/reader_position_tracker.dart';

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
    ReaderPositionTracker? tracker,
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
       tracker = tracker ?? ReaderPositionTracker();

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

  /// 逻辑位置追踪器（charOffset 事实源，模式切换与离场快照共用）。
  final ReaderPositionTracker tracker;

  ReaderPositionSnapshot? currentPosition;

  /// 释放 Facade 自建的通知器；页面自持通知器时通过自建 publisher 注入，
  /// 由页面负责其 dispose。
  void disposeOwnNotifier() {
    final notifier = publisher.notifier;
    notifier.dispose();
  }
}
