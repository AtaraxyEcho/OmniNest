import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:omninest/app/providers.dart';
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

class AdminUserState {
  const AdminUserState({
    required this.users,
    this.searchTerm = '',
    this.roleFilter,
    this.selectedIds = const {},
    this.total = 0,
  });

  final List<AdminUser> users;
  final String searchTerm;
  final String? roleFilter;
  final Set<String> selectedIds;
  final int total;

  List<AdminUser> get visibleUsers {
    final normalizedSearch = searchTerm.trim().toLowerCase();
    return users.where((user) {
      final matchesRole =
          roleFilter == null ||
          roleFilter!.isEmpty ||
          user.roles.contains(roleFilter);
      final matchesSearch =
          normalizedSearch.isEmpty ||
          user.username.toLowerCase().contains(normalizedSearch) ||
          (user.displayName ?? '').toLowerCase().contains(normalizedSearch) ||
          (user.email ?? '').toLowerCase().contains(normalizedSearch);
      return matchesRole && matchesSearch;
    }).toList();
  }

  bool get hasSelection => selectedIds.isNotEmpty;

  bool get hasMoreUsers => users.length < total;

  int countByRole(String role) {
    return users.where((user) => user.roles.contains(role)).length;
  }

  AdminUserState copyWith({
    List<AdminUser>? users,
    String? searchTerm,
    String? roleFilter,
    bool clearRoleFilter = false,
    Set<String>? selectedIds,
    bool clearSelection = false,
    int? total,
  }) {
    return AdminUserState(
      users: users ?? this.users,
      searchTerm: searchTerm ?? this.searchTerm,
      roleFilter: clearRoleFilter ? null : roleFilter ?? this.roleFilter,
      selectedIds: clearSelection ? const {} : selectedIds ?? this.selectedIds,
      total: total ?? this.total,
    );
  }
}

class AdminUserController extends AsyncNotifier<AdminUserState> {
  AdminUserApi get _api => ref.read(adminUserApiProvider);

  int _page = 0;
  bool _hasMore = true;
  bool _loadingUsers = false;
  static const _pageSize = 50;

  @override
  Future<AdminUserState> build() async {
    final result = await _api.listUsers(page: 0, size: _pageSize);
    _page = 1;
    _hasMore = result.items.length < result.total;
    return AdminUserState(users: result.items, total: result.total);
  }

  Future<void> refreshUsers() async {
    final current = state.asData?.value;
    _page = 0;
    _hasMore = true;
    final result = await _api.listUsers(page: 0, size: _pageSize);
    _page = 1;
    _hasMore = result.items.length < result.total;
    state = AsyncData(
      (current ?? const AdminUserState(users: [])).copyWith(
        users: result.items,
        total: result.total,
      ),
    );
  }

  Future<void> loadMoreUsers() async {
    if (_loadingUsers || !_hasMore) return;
    _loadingUsers = true;
    try {
      final result = await _api.listUsers(page: _page, size: _pageSize);
      final current = state.asData?.value;
      if (current == null) return;
      _hasMore = (current.users.length + result.items.length) < result.total;
      _page++;
      state = AsyncData(
        current.copyWith(
          users: [...current.users, ...result.items],
          total: result.total,
        ),
      );
    } finally {
      _loadingUsers = false;
    }
  }

  Future<void> createUser(AdminCreateUserInput input) async {
    await _api.createUser(input);
    await refreshUsers();
  }

  Future<void> updateUserStatus(String userId, String status) async {
    await _api.updateUserStatus(userId, status);
    await refreshUsers();
  }

  Future<void> updateUserRoles(String userId, Set<String> roles) async {
    await _api.updateUserRoles(userId, roles);
    await refreshUsers();
    // 修改自己所属角色时本地 JWT claims 已过期，轮换会话令牌。
    final currentUser = ref.read(authSessionProvider).asData?.value.user;
    if (currentUser != null && currentUser.id == userId) {
      unawaited(ref.read(authSessionProvider.notifier).refreshSession());
    }
  }

  Future<void> updateUserQuota(String userId, int quotaBytes) async {
    await _api.updateUserQuota(userId, quotaBytes);
    await refreshUsers();
  }

  Future<int> batchUpdateQuota(List<String> userIds, int quotaBytes) async {
    final updated = await _api.batchUpdateQuota(userIds, quotaBytes);
    await refreshUsers();
    return updated;
  }

  void toggleSelection(String userId) {
    final current = state.asData?.value;
    if (current == null) return;
    final ids = Set<String>.of(current.selectedIds);
    if (ids.contains(userId)) {
      ids.remove(userId);
    } else {
      ids.add(userId);
    }
    state = AsyncData(current.copyWith(selectedIds: ids));
  }

  void selectAllVisible() {
    final current = state.asData?.value;
    if (current == null) return;
    final visibleIds =
        current.visibleUsers
            .where((u) => !u.isSuperAdmin)
            .map((u) => u.id)
            .toSet();
    state = AsyncData(current.copyWith(selectedIds: visibleIds));
  }

  void clearSelection() {
    final current = state.asData?.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(clearSelection: true));
  }

  void setSearchTerm(String value) {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    state = AsyncData(current.copyWith(searchTerm: value));
  }

  void setRoleFilter(String? role) {
    final current = state.asData?.value;
    if (current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(roleFilter: role, clearRoleFilter: role == null),
    );
  }
}
