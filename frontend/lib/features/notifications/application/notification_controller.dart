import 'dart:async';
import 'package:omninest/app/session/session_epoch.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/realtime_providers.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/features/notifications/application/notification_foreground_presenter.dart';
import 'package:omninest/features/notifications/data/notification_api.dart';
import 'package:omninest/features/notifications/domain/notification_models.dart';
import 'package:omninest/core/log/dev_log.dart';

final notificationApiProvider = Provider<NotificationApi>((ref) {
  return NotificationApi(ref.watch(apiClientProvider));
});

final notificationRealtimeSubscriptionProvider =
    Provider<StreamSubscription<Map<String, dynamic>>?>((ref) {
      final coordinator = ref.watch(realtimeCoordinatorProvider);
      if (coordinator == null) {
        return null;
      }
      final subscription = coordinator.notificationMessages.listen((json) {
        try {
          final notification = NotificationDto.fromJson(json);
          final inserted = ref
              .read(notificationControllerProvider.notifier)
              .prepend(notification);
          if (inserted && !notification.read) {
            ref.read(unreadCountProvider.notifier).increment();
          }
          // 转发到前台提示广播流，根部提示组件消费展示。
          ref
              .read(notificationForegroundEventControllerProvider)
              .add(notification);
        } catch (_) {
          return;
        }
      });
      ref.onDispose(() => unawaited(subscription.cancel()));
      return subscription;
    });

final unreadCountProvider = NotifierProvider<UnreadCountNotifier, int>(
  UnreadCountNotifier.new,
);

/// 维护通知未读数量。
class UnreadCountNotifier extends Notifier<int> {
  @override
  int build() {
    ref.watch(sessionEpochProvider);
    // 只跟随登录用户身份：同用户 token 刷新不重建，换号/登出重置计数。
    final userId = ref.watch(
      authSessionProvider.select((async) => async.asData?.value.user?.id),
    );
    if (userId != null) {
      unawaited(_loadInitialCount());
    }
    return 0;
  }

  Future<void> _loadInitialCount() async {
    try {
      final count = await ref.read(notificationApiProvider).unreadCount();
      if (ref.mounted) {
        state = count;
      }
    } on Exception catch (error) {
      if (kDebugMode) {
        devLog('通知未读数初始化失败: ${error.runtimeType}');
      }
    }
  }

  void increment() => state++;

  void set(int value) => state = value;

  /// 从服务端严格刷新未读数量。
  Future<void> refresh() async {
    state = await ref.read(notificationApiProvider).unreadCount();
  }
}

/// 通知中心筛选档位。
enum NotificationFilter { all, unread }

/// 通知列表状态
class NotificationState {
  const NotificationState({
    this.items = const [],
    this.total = 0,
    this.allTotal = 0,
    this.currentPage = 0,
    this.filter = NotificationFilter.all,
    this.isLoading = false,
  });

  final List<NotificationDto> items;

  /// 当前筛选下的通知总数（分页 totalElements）。
  final int total;

  /// 全部通知总数快照：仅在 all 筛选加载时更新，供未读视图下
  /// 「全部通知 (n)」标签展示最近已知值。
  final int allTotal;

  final int currentPage;

  final NotificationFilter filter;

  final bool isLoading;

  NotificationState copyWith({
    List<NotificationDto>? items,
    int? total,
    int? allTotal,
    int? currentPage,
    NotificationFilter? filter,
    bool? isLoading,
  }) {
    return NotificationState(
      items: items ?? this.items,
      total: total ?? this.total,
      allTotal: allTotal ?? this.allTotal,
      currentPage: currentPage ?? this.currentPage,
      filter: filter ?? this.filter,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

/// 通知控制器 Provider
final notificationControllerProvider =
    NotifierProvider<NotificationController, NotificationState>(
      NotificationController.new,
    );

/// 通知控制器 — 管理通知列表状态
class NotificationController extends Notifier<NotificationState> {
  @override
  NotificationState build() {
    ref.watch(sessionEpochProvider);
    return const NotificationState();
  }

  NotificationApi get _api => ref.read(notificationApiProvider);

  Future<void>? _activeOperation;
  Future<void>? _realtimeRefresh;

  bool get _unreadOnly => state.filter == NotificationFilter.unread;

  /// 加载通知列表（当前筛选）。
  Future<void> load({int page = 0, int size = 20}) async {
    if (_activeOperation != null) return;
    final operation = _loadPage(page: page, size: size);
    _activeOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_activeOperation, operation)) {
        _activeOperation = null;
      }
    }
  }

  /// 切换筛选档位并回到第一页。
  Future<void> setFilter(NotificationFilter filter, {int size = 20}) async {
    if (state.filter == filter) return;
    state = state.copyWith(filter: filter, currentPage: 0, isLoading: true);
    await load(page: 0, size: size);
  }

  /// 跳转到指定页（0 基）。
  Future<void> goToPage(int page, {int size = 20}) async {
    if (page < 0 || page == state.currentPage) return;
    await load(page: page, size: size);
  }

  /// 严格刷新当前通知分页，失败时保留失效记录等待重试。
  Future<void> refreshForRealtime({int size = 20}) async {
    final existing = _realtimeRefresh;
    if (existing != null) {
      await existing;
      return;
    }
    final operation = _refreshAfterCurrentOperation(size);
    _realtimeRefresh = operation;
    try {
      await operation;
    } finally {
      if (identical(_realtimeRefresh, operation)) {
        _realtimeRefresh = null;
      }
    }
  }

  Future<void> _refreshAfterCurrentOperation(int size) async {
    final active = _activeOperation;
    if (active != null) {
      await active;
    }
    final operation = _refreshPages(size);
    _activeOperation = operation;
    try {
      await operation;
    } finally {
      if (identical(_activeOperation, operation)) {
        _activeOperation = null;
      }
    }
  }

  Future<void> _refreshPages(int size) async {
    final current = state;
    final pages = await Future.wait([
      for (var page = 0; page <= current.currentPage; page++)
        _api.list(page: page, size: size, unreadOnly: _unreadOnly),
    ]);
    state = NotificationState(
      items: pages.expand((page) => page.items).toList(growable: false),
      total: pages.last.total,
      allTotal: _unreadOnly ? current.allTotal : pages.last.total,
      currentPage: current.currentPage,
      filter: current.filter,
    );
  }

  /// 在列表头部插入一条通知（WebSocket 推送时使用）。
  /// 未读筛选视图下已读推送不可见；total/allTotal 分别跟随可见性与全量。
  bool prepend(NotificationDto notification) {
    final exists = state.items.any((item) => item.id == notification.id);
    final visibleInFilter = !_unreadOnly || !notification.read;
    state = state.copyWith(
      items:
          visibleInFilter
              ? [
                notification,
                for (final item in state.items)
                  if (item.id != notification.id) item,
              ]
              : state.items,
      total: !exists && visibleInFilter ? state.total + 1 : state.total,
      allTotal: !exists ? state.allTotal + 1 : state.allTotal,
    );
    return !exists;
  }

  Future<void> _loadPage({required int page, required int size}) async {
    state = state.copyWith(isLoading: true);
    try {
      final unreadOnly = _unreadOnly;
      final result = await _api.list(
        page: page,
        size: size,
        unreadOnly: unreadOnly,
      );
      state = NotificationState(
        items: result.items,
        total: result.total,
        allTotal: unreadOnly ? state.allTotal : result.total,
        currentPage: page,
        filter: state.filter,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// 标记指定通知为已读。未读筛选视图下已读条目随即移出列表。
  Future<void> markRead(String id) async {
    final wasUnread = state.items.any((item) => item.id == id && !item.read);
    await _api.markRead([id]);
    if (_unreadOnly) {
      state = state.copyWith(
        items: [
          for (final n in state.items)
            if (n.id != id) n,
        ],
        total: (state.total - 1).clamp(0, state.total),
      );
    } else {
      state = state.copyWith(
        items: [
          for (final n in state.items)
            if (n.id == id) n.copyWith(read: true) else n,
        ],
      );
    }
    if (wasUnread) {
      final unread = ref.read(unreadCountProvider);
      ref.read(unreadCountProvider.notifier).set((unread - 1).clamp(0, unread));
    }
  }

  /// 全部标记已读。未读筛选视图下列表清空。
  Future<void> markAllRead() async {
    await _api.markAllRead();
    if (_unreadOnly) {
      state = state.copyWith(items: [], total: 0);
    } else {
      state = state.copyWith(
        items: [for (final n in state.items) n.copyWith(read: true)],
      );
    }
    ref.read(unreadCountProvider.notifier).set(0);
  }

  /// 删除指定通知。
  Future<void> deleteNotification(String id) async {
    final notification = state.items.where((item) => item.id == id).firstOrNull;
    await _api.deleteNotification(id);
    state = state.copyWith(
      items: [
        for (final item in state.items)
          if (item.id != id) item,
      ],
      total: (state.total - 1).clamp(0, state.total),
      allTotal: (state.allTotal - 1).clamp(0, state.allTotal),
    );
    if (notification != null && !notification.read) {
      final unread = ref.read(unreadCountProvider);
      ref.read(unreadCountProvider.notifier).set((unread - 1).clamp(0, unread));
    }
  }

  /// 清空当前账户的全部通知。
  Future<void> clearAll() async {
    await _api.clearAll();
    state = NotificationState(filter: state.filter);
    ref.read(unreadCountProvider.notifier).set(0);
  }
}
