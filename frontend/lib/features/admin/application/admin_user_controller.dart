import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
import 'package:omninest/app/session/session_epoch.dart';
import 'package:omninest/core/auth/auth_controller.dart';
import 'package:omninest/features/admin/data/admin_user_api.dart';
import 'package:omninest/features/admin/domain/admin_user.dart';

final adminUserApiProvider = Provider<AdminUserApi>((ref) {
  return AdminUserApi(ref.watch(apiClientProvider));
});

final adminUserControllerProvider =
    AsyncNotifierProvider<AdminUserController, AdminUserState>(
      AdminUserController.new,
    );

/// 用户管理页状态：服务端分页当前页数据 + 筛选、排序与选择集。
class AdminUserState {
  const AdminUserState({
    required this.users,
    this.query = '',
    this.roleFilter = 'ALL',
    this.selectedIds = const {},
    this.page = 0,
    this.pageSize = defaultPageSize,
    this.totalElements = 0,
    this.sortField = defaultSortField,
    this.sortAscending = true,
  });

  /// 初始页大小，build 首拉与筛选重置共用，避免魔法数字散落。
  static const int defaultPageSize = 10;

  /// 默认排序字段，与后端白名单回退值保持一致。
  static const String defaultSortField = 'username';

  final List<AdminUser> users;
  final String query;
  final String roleFilter;
  final Set<String> selectedIds;

  final int page;
  final int pageSize;
  final int totalElements;

  /// 服务端排序字段（后端白名单内的实体属性名）。
  final String sortField;

  final bool sortAscending;

  int get totalPages =>
      totalElements <= 0 ? 0 : (totalElements / pageSize).ceil();

  bool get hasSelection => selectedIds.isNotEmpty;

  AdminUserState copyWith({
    List<AdminUser>? users,
    String? query,
    String? roleFilter,
    Set<String>? selectedIds,
    bool clearSelection = false,
    int? page,
    int? pageSize,
    int? totalElements,
    String? sortField,
    bool? sortAscending,
  }) {
    return AdminUserState(
      users: users ?? this.users,
      query: query ?? this.query,
      roleFilter: roleFilter ?? this.roleFilter,
      selectedIds: clearSelection ? const {} : selectedIds ?? this.selectedIds,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      totalElements: totalElements ?? this.totalElements,
      sortField: sortField ?? this.sortField,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }
}

/// 用户管理控制器：服务端分页 + 搜索/角色筛选直传后端。
///
/// 翻页与筛选变更会重置回第一页并清空批量选择；写操作后原地刷新
/// 当前页并保留选择集；实时事件触发的刷新额外把选择集修剪为当前
/// 页仍存在的用户。
class AdminUserController extends AsyncNotifier<AdminUserState> {
  AdminUserApi get _api => ref.read(adminUserApiProvider);

  Timer? _searchDebounce;
  bool _fetching = false;

  /// _fetching 期间被丢弃的请求参数；当前请求收尾后重放，防止防抖搜索
  /// 被"正在拉取"静默吞掉导致搜索词与列表口径失配。
  ({
    int page,
    int pageSize,
    String query,
    String roleFilter,
    String sortField,
    bool sortAscending,
    bool resetSelection,
    bool pruneSelection,
  })?
  _droppedFetch;

  @override
  Future<AdminUserState> build() async {
    ref.watch(sessionEpochProvider);
    ref.onDispose(() => _searchDebounce?.cancel());
    return _fetchInitialState();
  }

  /// 首次进入即拉取第一页。
  ///
  /// 分区切换 invalidate 与会话世代变化都会重建本 provider；若 build 只
  /// 返回空 state，页面会停留在空表直到用户手动触发筛选。这里保持无
  /// 副作用（不读写 [_fetching] 等实例字段），直接请求默认首页并返回
  /// 全新 state。
  Future<AdminUserState> _fetchInitialState() async {
    final result = await _api.listUsers(
      page: 0,
      size: AdminUserState.defaultPageSize,
      query: '',
      role: 'ALL',
    );
    return AdminUserState(
      users: result.items,
      totalElements: result.total,
      pageSize: AdminUserState.defaultPageSize,
    );
  }

  Future<void> _fetch({
    int? page,
    int? pageSize,
    String? query,
    String? roleFilter,
    String? sortField,
    bool? sortAscending,
    bool resetSelection = false,
    bool pruneSelection = false,
  }) async {
    if (_fetching) {
      final latest = state.asData?.value;
      _droppedFetch = (
        page: page ?? latest?.page ?? 0,
        pageSize:
            pageSize ?? latest?.pageSize ?? AdminUserState.defaultPageSize,
        query: query ?? latest?.query ?? '',
        roleFilter: roleFilter ?? latest?.roleFilter ?? 'ALL',
        sortField:
            sortField ?? latest?.sortField ?? AdminUserState.defaultSortField,
        sortAscending: sortAscending ?? latest?.sortAscending ?? true,
        resetSelection: resetSelection,
        pruneSelection: pruneSelection,
      );
      return;
    }
    _fetching = true;
    final current = state.asData?.value ?? const AdminUserState(users: []);
    final targetPage = page ?? current.page;
    final targetSize = pageSize ?? current.pageSize;
    final targetQuery = query ?? current.query;
    final targetRole = roleFilter ?? current.roleFilter;
    final targetSortField = sortField ?? current.sortField;
    final targetAscending = sortAscending ?? current.sortAscending;
    try {
      final result = await _api.listUsers(
        page: targetPage,
        size: targetSize,
        query: targetQuery,
        role: targetRole,
        sort: targetSortField,
        dir: targetAscending ? 'asc' : 'desc',
      );
      // 回写基于 await 返回后的最新状态：copyWith 未传 selectedIds 时保留
      // 最新选择，避免飞行期间的勾选被 await 前快照回滚。
      final latest = state.asData?.value ?? const AdminUserState(users: []);
      state = AsyncData(
        latest.copyWith(
          users: result.items,
          query: targetQuery,
          roleFilter: targetRole,
          page: targetPage,
          pageSize: targetSize,
          totalElements: result.total,
          sortField: targetSortField,
          sortAscending: targetAscending,
          selectedIds:
              pruneSelection
                  ? _selectionOnPage(latest.selectedIds, result.items)
                  : null,
          clearSelection: resetSelection,
        ),
      );
    } finally {
      _fetching = false;
      final dropped = _droppedFetch;
      if (dropped != null) {
        _droppedFetch = null;
        unawaited(
          _fetch(
            page: dropped.page,
            pageSize: dropped.pageSize,
            query: dropped.query,
            roleFilter: dropped.roleFilter,
            sortField: dropped.sortField,
            sortAscending: dropped.sortAscending,
            resetSelection: dropped.resetSelection,
            pruneSelection: dropped.pruneSelection,
          ),
        );
      }
    }
  }

  /// 搜索词防抖 300ms 后回第一页；同值重复触发不请求。
  void setSearchTerm(String value) {
    final current = state.asData?.value;
    if (current == null || current.query == value) {
      return;
    }
    state = AsyncData(current.copyWith(query: value));
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _fetch(page: 0, resetSelection: true);
    });
  }

  void setRoleFilter(String role) {
    final current = state.asData?.value;
    if (current == null || current.roleFilter == role) {
      return;
    }
    _fetch(page: 0, roleFilter: role, resetSelection: true);
  }

  /// 切换服务端排序；同字段同方向不重复请求，变更后回第一页并清空
  /// 批量选择（行序变化后跨序保留选择没有操作意义）。
  void setSort(String sortField, bool ascending) {
    final current = state.asData?.value;
    if (current == null ||
        (current.sortField == sortField &&
            current.sortAscending == ascending)) {
      return;
    }
    _fetch(
      page: 0,
      sortField: sortField,
      sortAscending: ascending,
      resetSelection: true,
    );
  }

  void setPage(int page) {
    _fetch(page: page, resetSelection: true);
  }

  void setPageSize(int size) {
    _fetch(page: 0, pageSize: size, resetSelection: true);
  }

  /// 实时事件后的原地刷新：保留当前页码、筛选与批量选中集，仅把
  /// 选中集修剪为刷新后仍在当前页的用户，避免批量操作计数与可见行
  /// 不一致；翻页/筛选等用户主动变更仍走各自的清空语义。
  Future<void> refreshUsers() async {
    await _fetch(pruneSelection: true);
  }

  Future<void> createUser(AdminCreateUserInput input) async {
    await _api.createUser(input);
    await _fetch(resetSelection: true);
  }

  Future<void> updateUserStatus(String userId, String status) async {
    await _api.updateUserStatus(userId, status);
    await _fetch();
  }

  Future<void> updateUserRoles(String userId, Set<String> roles) async {
    await _api.updateUserRoles(userId, roles);
    // 修改自己所属角色时本地 JWT claims 已过期，轮换会话令牌。
    final currentUser = ref.read(authSessionProvider).asData?.value.user;
    if (currentUser != null && currentUser.id == userId) {
      unawaited(ref.read(authSessionProvider.notifier).refreshSession());
    }
    await _fetch();
  }

  Future<void> updateUserQuota(String userId, int quotaBytes) async {
    await _api.updateUserQuota(userId, quotaBytes);
    await _fetch();
  }

  Future<int> batchUpdateQuota(List<String> userIds, int quotaBytes) async {
    final updated = await _api.batchUpdateQuota(userIds, quotaBytes);
    await _fetch();
    return updated;
  }

  /// 批量更新用户状态：后端逐项执行并返回失败清单；
  /// 完成后清空选择并刷新列表（选中集内的行状态已变化，保留无意义）。
  Future<({int successCount, List<String> failedIds})> batchUpdateUserStatus(
    List<String> userIds,
    String status,
  ) async {
    final result = await _api.batchUpdateUserStatus(userIds, status);
    await _fetch(resetSelection: true);
    return result;
  }

  Future<void> deleteUser(String userId) async {
    await _api.deleteUser(userId);
    await _fetch(resetSelection: true);
  }

  void toggleSelection(String userId) {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    final ids = Set<String>.of(current.selectedIds);
    if (ids.contains(userId)) {
      ids.remove(userId);
    } else {
      ids.add(userId);
    }
    state = AsyncData(current.copyWith(selectedIds: ids));
  }

  /// 全选当前页（超级管理员除外）；已全选时清空。
  void selectAllVisible() {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    final visibleIds =
        current.users.where((u) => !u.isSuperAdmin).map((u) => u.id).toSet();
    // 当前页没有可勾选项（如只剩受保护的超管行）时清空选择，
    // 避免表头 every() 空迭代恒真导致的"假选中且点击无效"。
    if (visibleIds.isEmpty) {
      state = AsyncData(current.copyWith(clearSelection: true));
      return;
    }
    final allSelected = current.selectedIds.containsAll(visibleIds);
    final next = allSelected ? const <String>{} : visibleIds;
    state = AsyncData(current.copyWith(selectedIds: next));
  }

  void clearSelection() {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    state = AsyncData(current.copyWith(clearSelection: true));
  }

  /// 把选中集修剪为给定用户页仍存在的 id。
  static Set<String> _selectionOnPage(Set<String> ids, List<AdminUser> users) {
    final visibleIds = users.map((user) => user.id).toSet();
    return ids.where(visibleIds.contains).toSet();
  }
}
