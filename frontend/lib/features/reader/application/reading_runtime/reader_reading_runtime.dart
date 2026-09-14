import 'package:flutter/foundation.dart';

import 'package:omninest/features/reader/application/reader_progress_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_event_log.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_geometry_commit.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_geometry_invalidation.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_geometry_scheduler.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_geometry_store.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_operation_token.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_persistence_queue.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_resolver.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_snapshot.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_position_state.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_progress_projection.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_progress_publisher.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_restore_manager.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_clock.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_diagnostics.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_runtime_identity.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_scroll_effect.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_transaction_manager.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_visual_extent_table.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_wheel_burst_tracker.dart';
import 'package:omninest/features/reader/application/reading_runtime/reader_window_manager.dart';

/// Reader Reading Runtime Facade（方案 §83/§64 终态）：页面只经此访问运行时。
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
    ReaderOperationToken? operationToken,
    ReaderPositionState? positionState,
    ReaderGeometryScheduler? geometryScheduler,
    ReaderScrollEffect? scrollEffect,
    void Function(ReaderProgressSnapshot snapshot)? onPersistEnqueue,
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
       geometryCommit = geometryCommit ?? const ReaderGeometryCommit(),
       operationToken = operationToken ?? ReaderOperationToken(),
       positionState = positionState ?? ReaderPositionState(),
       geometryScheduler = geometryScheduler ?? ReaderGeometryScheduler(),
       persistenceQueue = ReaderPersistenceQueue(
         onEnqueue: onPersistEnqueue ?? (_) {},
       ),
       wheelBurst = ReaderWheelBurstTracker(
         clock: clock ?? const SystemReaderRuntimeClock(),
       );

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

  /// 滚轮/触控板 burst 跟踪（方案 §30/§31，时钟经 §109 注入）。
  final ReaderWheelBurstTracker wheelBurst;

  /// 事件日志（方案 §103/§126）：环形缓冲 + 实机验收格式。
  final ReaderRuntimeEventLog eventLog = ReaderRuntimeEventLog();

  /// Runtime 操作令牌（新方案 §35/§43）：在途异步操作的生命周期凭证。
  final ReaderOperationToken operationToken;

  /// 位置状态（新方案 §30）：transient / committed 双位置。
  final ReaderPositionState positionState;

  /// Geometry 提交调度（新方案 §25/§42）：手势期间挂起、终端提交。
  final ReaderGeometryScheduler geometryScheduler;

  /// 持久化队列（新方案 §28/§30）：committedPosition 投影的唯一出口。
  final ReaderPersistenceQueue persistenceQueue;

  /// 物理滚动适配器（新方案 §43/§63）：页面注入，Runtime 不持有 Controller。
  ReaderScrollEffect? scrollEffect;

  /// 运行时身份（新方案 §57）：模式切换时更新。
  ReaderRuntimeIdentity? identity;

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
