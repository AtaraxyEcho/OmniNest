import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/app/environment.dart';
import 'package:omninest/core/network/api_client.dart';
import 'package:omninest/features/notifications/application/notification_controller.dart';
import 'package:omninest/features/notifications/data/notification_api.dart';
import 'package:omninest/features/notifications/domain/notification_models.dart';

/// 通知中心筛选与分页语义回归：
/// - setFilter(unread) 以 unreadOnly=true 回到第一页；
/// - 未读视图下 markRead 将条目移出列表并递减 total；
/// - 已读推送在未读视图不可见，但计入 allTotal；
/// - 全部视图 markRead 就地置已读。
void main() {
  late _FakeNotificationApi api;
  late ProviderContainer container;

  setUp(() {
    api = _FakeNotificationApi();
    container = ProviderContainer.test(
      overrides: [notificationApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    container.listen(notificationControllerProvider, (_, _) {});
  });

  NotificationController controller() =>
      container.read(notificationControllerProvider.notifier);

  test('setFilter 切换未读筛选时以 unreadOnly 重新加载第一页', () async {
    await controller().load();
    expect(
      container.read(notificationControllerProvider).filter,
      NotificationFilter.all,
    );

    await controller().setFilter(NotificationFilter.unread);

    final state = container.read(notificationControllerProvider);
    expect(state.filter, NotificationFilter.unread);
    expect(state.currentPage, 0);
    expect(api.listCalls.last, (
      page: 0,
      unreadOnly: true,
    ), reason: '未读筛选必须携带 unreadOnly=true');
    expect(state.items, hasLength(2));
    expect(state.total, 2);
  });

  test('未读视图 markRead 移出条目并递减 total', () async {
    await controller().setFilter(NotificationFilter.unread);
    final target = container.read(notificationControllerProvider).items.first;

    await controller().markRead(target.id);

    final state = container.read(notificationControllerProvider);
    expect(state.items.where((item) => item.id == target.id), isEmpty);
    expect(state.total, 1);
  });

  test('未读视图 markAllRead 清空列表', () async {
    await controller().setFilter(NotificationFilter.unread);

    await controller().markAllRead();

    final state = container.read(notificationControllerProvider);
    expect(state.items, isEmpty);
    expect(state.total, 0);
  });

  test('未读视图 prepend 已读推送不可见但计入 allTotal', () async {
    await controller().setFilter(NotificationFilter.unread);
    final before = container.read(notificationControllerProvider);

    final insertedRead = controller().prepend(
      NotificationDto(
        id: 'read-live',
        type: 'SYSTEM_MESSAGE',
        title: '已读推送',
        read: true,
        createdAt: DateTime.now(),
      ),
    );

    expect(insertedRead, isTrue, reason: '新通知仍需驱动未读数与前台提示');
    final after = container.read(notificationControllerProvider);
    expect(after.items, hasLength(before.items.length));
    expect(after.total, before.total);
    expect(after.allTotal, before.allTotal + 1);
  });

  test('loadMore 追加下一页并按 id 去重，越界不再请求', () async {
    final paged = _PagedNotificationApi();
    final box = ProviderContainer.test(
      overrides: [notificationApiProvider.overrideWithValue(paged)],
    );
    addTearDown(box.dispose);
    box.listen(notificationControllerProvider, (_, _) {});
    final pagedController = box.read(notificationControllerProvider.notifier);

    await pagedController.load(size: 2);
    var state = box.read(notificationControllerProvider);
    expect(state.items.map((item) => item.id), ['a', 'b']);
    expect(state.currentPage, 0);

    // 第二页返回 [b, c]：重复 id b 去重后仅追加 c。
    await pagedController.loadMore(size: 2);
    state = box.read(notificationControllerProvider);
    expect(state.items.map((item) => item.id), ['a', 'b', 'c']);
    expect(state.currentPage, 1);
    expect(state.isLoading, isFalse);

    // total=5、size=2 共 3 页（0-2）：第三页仍返回 [b, c]，去重后不变。
    await pagedController.loadMore(size: 2);
    state = box.read(notificationControllerProvider);
    expect(state.items.map((item) => item.id), ['a', 'b', 'c']);
    expect(state.currentPage, 2);

    // 越过最后一页后不再发起请求。
    final callsBefore = paged.listCalls.length;
    await pagedController.loadMore(size: 2);
    expect(paged.listCalls.length, callsBefore);
    expect(box.read(notificationControllerProvider).currentPage, 2);
  });

  test('全部视图 markRead 就地置已读且 total 不变', () async {
    await controller().load();
    final target = container.read(notificationControllerProvider).items.first;

    await controller().markRead(target.id);

    final state = container.read(notificationControllerProvider);
    expect(state.items.firstWhere((item) => item.id == target.id).read, isTrue);
    expect(state.total, 3);
  });
}

/// 分页去重回归专用：total=5，页 0 返回 [a, b]，页 1 返回 [b, c]。
class _PagedNotificationApi extends _FakeNotificationApi {
  @override
  Future<({List<NotificationDto> items, int total})> list({
    int page = 0,
    int size = 20,
    bool unreadOnly = false,
  }) async {
    listCalls.add((page: page, unreadOnly: unreadOnly));
    final ids = page == 0 ? ['a', 'b'] : ['b', 'c'];
    final List<NotificationDto> items = [
      for (final id in ids) _FakeNotificationApi._dto(id, false),
    ];
    return (items: items, total: 5);
  }
}

class _FakeNotificationApi extends NotificationApi {
  _FakeNotificationApi()
    : super(
        ApiClient(
          const AppEnvironment(
            apiBaseUrl: 'http://localhost:8080/api/v1',
            wsBaseUrl: 'ws://localhost:8080/ws',
          ),
        ),
      );

  final listCalls = <({int page, bool unreadOnly})>[];
  final markReadIds = <String>[];

  static NotificationDto _dto(String id, bool read) {
    return NotificationDto(
      id: id,
      type: 'SYSTEM_MESSAGE',
      title: '标题 $id',
      message: null,
      read: read,
      createdAt: DateTime(2026, 9, 28, 9),
    );
  }

  @override
  Future<({List<NotificationDto> items, int total})> list({
    int page = 0,
    int size = 20,
    bool unreadOnly = false,
  }) async {
    listCalls.add((page: page, unreadOnly: unreadOnly));
    if (unreadOnly) {
      return (items: [_dto('n-1', false), _dto('n-2', false)], total: 2);
    }
    return (
      items: [_dto('n-1', false), _dto('n-2', false), _dto('n-3', true)],
      total: 3,
    );
  }

  @override
  Future<void> markRead(List<String> ids) async {
    markReadIds.addAll(ids);
  }

  @override
  Future<void> markAllRead() async {}

  @override
  Future<void> deleteNotification(String notificationId) async {}

  @override
  Future<void> clearAll() async {}

  @override
  Future<int> unreadCount() async => 0;
}
