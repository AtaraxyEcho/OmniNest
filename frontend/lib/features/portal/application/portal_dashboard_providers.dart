import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/realtime_providers.dart';
import 'package:omninest/core/realtime/realtime_models.dart';
import 'package:omninest/features/admin/admin_dashboard.dart';
import 'package:omninest/features/files/file_dashboard.dart';
import 'package:omninest/features/music/music_portal.dart';
import 'package:omninest/features/photos/photo_dashboard.dart';
import 'package:omninest/features/portal/portal_weather.dart';
import 'package:omninest/features/reader/reader_dashboard.dart';
import 'package:omninest/features/video/video_dashboard.dart';

final portalStorageStatsProvider = fileStorageStatsProvider;

final portalMovieDashboardProvider = movieDashboardProvider;

final portalMusicSnapshotProvider = musicPortalSnapshotProvider;

final portalMusicPlaybackTimelineProvider = musicPortalPlaybackTimelineProvider;

final portalMusicActionsProvider = musicPortalActionsProvider;

final portalPhotoDashboardProvider = photoDashboardProvider;

final portalAdminSummaryProvider = adminConsoleSummaryProvider;

final portalReaderDashboardProvider = readerDashboardProvider;

/// Portal 可独立刷新的摘要分区。
enum PortalDashboardSection {
  storage,
  video,
  music,
  photos,
  reader,
  admin,
  weather,
}

/// 一次 Portal 刷新的分区结果。
class PortalDashboardRefreshResult {
  const PortalDashboardRefreshResult({required this.failedSections});

  final Set<PortalDashboardSection> failedSections;

  bool get succeeded => failedSections.isEmpty;
}

/// Portal 摘要刷新入口，单个分区失败不会中断其他分区。
///
/// 内建两类防护，保证实时脏事件风暴不会演变为请求风暴：
/// 同一分区刷新在飞时不重复发起（收尾后至多补一次尾部刷新），且距上次
/// 刷新不足节流窗口的分区直接跳过；显式 force 仅用于用户手动刷新。
class PortalDashboardActions {
  PortalDashboardActions(
    Map<PortalDashboardSection, Future<void> Function()> refreshers, {
    bool Function()? hasCachedData,
    this.sectionThrottle = const Duration(seconds: 4),
    this.fullRefreshInterval = const Duration(seconds: 30),
  }) : _refreshers = Map.unmodifiable(refreshers),
       _hasCachedData = hasCachedData;

  final Map<PortalDashboardSection, Future<void> Function()> _refreshers;
  final bool Function()? _hasCachedData;

  /// 同一分区两次刷新之间的最小间隔。
  final Duration sectionThrottle;

  /// 两次全量刷新之间的最小间隔（窗口聚焦等场景的节流）。
  final Duration fullRefreshInterval;

  final Set<PortalDashboardSection> _inFlight = <PortalDashboardSection>{};
  final Set<PortalDashboardSection> _trailing = <PortalDashboardSection>{};
  final Map<PortalDashboardSection, DateTime> _lastRefreshAt =
      <PortalDashboardSection, DateTime>{};
  DateTime? _lastFullRefreshAt;

  Future<PortalDashboardRefreshResult> refreshAll({bool force = false}) async {
    _lastFullRefreshAt = DateTime.now();
    final outcomes = await Future.wait(
      PortalDashboardSection.values.map((section) async {
        final succeeded = await retry(section, force: force);
        return (section: section, succeeded: succeeded);
      }),
    );
    return PortalDashboardRefreshResult(
      failedSections: {
        for (final outcome in outcomes)
          if (!outcome.succeeded) outcome.section,
      },
    );
  }

  /// 进入 Portal 时刷新：仅当摘要已有缓存数据（重进页面）才执行，
  /// 首次加载交由 providers 自身完成，避免双倍请求。
  Future<void> refreshOnEntry() async {
    if (!(_hasCachedData?.call() ?? true)) {
      return;
    }
    await maybeRefreshAll();
  }

  /// 分支重返时刷新封面关键分区：不受全量 30s 节流约束，
  /// 各分区自身仍有节流与在飞去重；与全量刷新并发时会被去重合并。
  Future<void> refreshCoverSections() async {
    await Future.wait([
      retry(PortalDashboardSection.video),
      retry(PortalDashboardSection.music),
      retry(PortalDashboardSection.photos),
      retry(PortalDashboardSection.reader),
    ]);
  }

  /// 窗口重新聚焦等场景的节流全量刷新。
  Future<void> maybeRefreshAll() async {
    final last = _lastFullRefreshAt;
    if (last != null && DateTime.now().difference(last) < fullRefreshInterval) {
      return;
    }
    await refreshAll();
  }

  Future<bool> retry(
    PortalDashboardSection section, {
    bool force = false,
  }) async {
    final refresher = _refreshers[section];
    if (refresher == null) {
      return false;
    }
    if (_inFlight.contains(section)) {
      _trailing.add(section);
      return true;
    }
    final last = _lastRefreshAt[section];
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < sectionThrottle) {
      return true;
    }
    _inFlight.add(section);
    try {
      await refresher();
      _lastRefreshAt[section] = DateTime.now();
      return true;
    } on Object {
      return false;
    } finally {
      _inFlight.remove(section);
      if (_trailing.remove(section)) {
        unawaited(retry(section, force: true));
      }
    }
  }
}

final portalDashboardActionsProvider = Provider<PortalDashboardActions>((ref) {
  return PortalDashboardActions(
    {
      PortalDashboardSection.storage: () async {
        ref.invalidate(portalStorageStatsProvider);
        await ref.read(portalStorageStatsProvider.future);
      },
      PortalDashboardSection.video: () async {
        ref.invalidate(portalMovieDashboardProvider);
        await ref.read(portalMovieDashboardProvider.future);
      },
      PortalDashboardSection.music:
          () => ref.read(portalMusicActionsProvider).refresh(),
      PortalDashboardSection.photos: () async {
        ref.invalidate(portalPhotoDashboardProvider);
        await ref.read(portalPhotoDashboardProvider.future);
      },
      PortalDashboardSection.reader: () async {
        ref.invalidate(portalReaderDashboardProvider);
        await ref.read(portalReaderDashboardProvider.future);
      },
      PortalDashboardSection.admin: () async {
        ref.invalidate(portalAdminSummaryProvider);
        await ref.read(portalAdminSummaryProvider.future);
      },
      PortalDashboardSection.weather: () async {
        ref.invalidate(realtimeWeatherProvider);
        await ref.read(realtimeWeatherProvider.future);
      },
    },
    hasCachedData:
        () =>
            ref.read(portalStorageStatsProvider).hasValue ||
            ref.read(portalMovieDashboardProvider).hasValue ||
            ref.read(portalPhotoDashboardProvider).hasValue ||
            ref.read(portalReaderDashboardProvider).hasValue ||
            ref.read(portalAdminSummaryProvider).hasValue,
  );
});

/// 脏事件到分区刷新的合并窗口；窗口内的高频事件只触发一轮分区刷新。
const Duration portalDirtyBatchWindow = Duration(milliseconds: 800);

/// 订阅实时脏范围并映射为 Portal 分区刷新。
///
/// 仅在 Portal 页面挂载期间存活（autoDispose）；密集脏事件先按
/// [portalDirtyBatchWindow] 合并，再交由 [PortalDashboardActions] 的
/// 节流与在飞保护兜底。
final portalDashboardRealtimeBinderProvider = Provider.autoDispose<void>((ref) {
  final stream = ref.watch(realtimeDirtyScopesStreamProvider);
  final actions = ref.watch(portalDashboardActionsProvider);
  if (stream == null) {
    return;
  }
  final pendingScopes = <RealtimeScope>{};
  Timer? batchTimer;
  StreamSubscription<Set<RealtimeScope>>? subscription;
  subscription = stream.listen((scopes) {
    pendingScopes.addAll(scopes);
    batchTimer ??= Timer(portalDirtyBatchWindow, () {
      batchTimer = null;
      final batch = pendingScopes.toList(growable: false);
      pendingScopes.clear();
      for (final scope in batch) {
        final section = _sectionForScope(scope);
        if (section != null) {
          unawaited(actions.retry(section));
        }
      }
    });
  });
  ref.onDispose(() {
    unawaited(subscription?.cancel());
    batchTimer?.cancel();
  });
});

/// 服务端同步范围到 Portal 分区的映射；无对应分区（天气/任务/偏好/
/// 通知）返回 null。
PortalDashboardSection? _sectionForScope(RealtimeScope scope) {
  return switch (scope) {
    RealtimeScope.files => PortalDashboardSection.storage,
    RealtimeScope.video => PortalDashboardSection.video,
    RealtimeScope.music => PortalDashboardSection.music,
    RealtimeScope.photos => PortalDashboardSection.photos,
    RealtimeScope.reader => PortalDashboardSection.reader,
    RealtimeScope.admin => PortalDashboardSection.admin,
    _ => null,
  };
}
