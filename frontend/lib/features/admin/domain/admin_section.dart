/// 管理台导航分区（样例 `Admin.tsx:15` 的 5 项，顺序一致）。
///
/// 分组即分区：每个分组是一张容器页，内部再用页签/卡片承载细分内容。
/// 旧版 10 个导航分区降为容器内页签，路由段全部保留为别名，避免深链失效。
enum AdminSectionGroup {
  overview(pathSegment: 'overview'),
  identity(pathSegment: 'identity'),
  operations(pathSegment: 'ops'),
  configuration(pathSegment: 'config'),
  storage(pathSegment: 'storage');

  const AdminSectionGroup({required this.pathSegment});

  /// 分组的 URL 段。样例用 `?admin=<sec>`，我方沿用已有的 `/admin/:section`。
  final String pathSegment;

  String get location => '/admin/$pathSegment';

  /// 进入分组时默认选中的页签。容器会在权限过滤后自动改选第一个可见页签。
  AdminSection get primary => switch (this) {
    AdminSectionGroup.overview => AdminSection.overview,
    AdminSectionGroup.identity => AdminSection.users,
    AdminSectionGroup.operations => AdminSection.tasks,
    AdminSectionGroup.configuration => AdminSection.config,
    AdminSectionGroup.storage => AdminSection.storage,
  };
}

/// 分区内的内容页签（原导航分区）。
enum AdminSection {
  overview(group: AdminSectionGroup.overview, pathSegment: 'overview'),
  logs(group: AdminSectionGroup.operations, pathSegment: 'logs'),
  tasks(group: AdminSectionGroup.operations, pathSegment: 'tasks'),
  sessions(group: AdminSectionGroup.operations, pathSegment: 'sessions'),
  maintenance(group: AdminSectionGroup.operations, pathSegment: 'maintenance'),
  users(group: AdminSectionGroup.identity, pathSegment: 'users'),
  roles(group: AdminSectionGroup.identity, pathSegment: 'roles'),
  config(group: AdminSectionGroup.configuration, pathSegment: 'config'),
  storage(group: AdminSectionGroup.storage, pathSegment: 'storage'),
  externalStorage(
    group: AdminSectionGroup.storage,
    pathSegment: 'external-storage',
  );

  const AdminSection({required this.group, required this.pathSegment});

  final AdminSectionGroup group;
  final String pathSegment;

  String get location => '/admin/$pathSegment';

  /// 分区可见所需的任一权限码。
  ///
  /// 与后端管理端接口的 @PreAuthorize 对齐；后端仍做最终校验。
  Set<String> get requiredAnyPermissions {
    return switch (this) {
      AdminSection.overview => {'system:config:read', 'system:user:read'},
      AdminSection.logs ||
      AdminSection.sessions ||
      AdminSection.config ||
      AdminSection.storage ||
      AdminSection.externalStorage => {'system:config:read'},
      AdminSection.tasks => {'task:admin'},
      AdminSection.maintenance => {
        'system:user:manage',
        'photo:admin',
        'media:library:manage',
      },
      AdminSection.users => {'system:user:read'},
      // 角色页同时依赖 /admin/roles 与 /admin/roles/detail
      AdminSection.roles => {'system:user:read', 'system:config:read'},
    };
  }

  bool isVisibleTo(Set<String> permissions) {
    return permissions.intersection(requiredAnyPermissions).isNotEmpty;
  }

  /// 5 个导航分区的入口；分组下任一页签可见就显示该分区。
  static List<AdminSection> visiblePrimary(Set<String> permissions) {
    return [
      for (final group in AdminSectionGroup.values)
        if (values.any(
          (section) =>
              section.group == group && section.isVisibleTo(permissions),
        ))
          group.primary,
    ];
  }

  /// 分组内对当前用户可见的页签，保持声明顺序。
  static List<AdminSection> visibleInGroup(
    AdminSectionGroup group,
    Set<String> permissions,
  ) => values
      .where(
        (section) => section.group == group && section.isVisibleTo(permissions),
      )
      .toList(growable: false);

  static AdminSection fromPathSegment(String? segment) {
    for (final section in values) {
      if (section.pathSegment == segment) {
        return section;
      }
    }
    // 新分组段（identity / ops）与旧段都解析成同一容器；旧段仍走上面的
    // 精确匹配，因此 /admin/logs 会直接选中日志页签而不是回到任务页签。
    if (segment == 'operations') {
      return AdminSectionGroup.operations.primary;
    }
    for (final group in AdminSectionGroup.values) {
      if (group.pathSegment == segment) {
        return group.primary;
      }
    }
    return AdminSection.overview;
  }

  static Map<AdminSectionGroup, List<AdminSection>> get grouped {
    return {
      for (final group in AdminSectionGroup.values)
        group: values
            .where((section) => section.group == group)
            .toList(growable: false),
    };
  }

  static Map<AdminSectionGroup, List<AdminSection>> visibleGrouped(
    Set<String> permissions,
  ) {
    return {
      for (final entry in grouped.entries)
        if (entry.value.any((section) => section.isVisibleTo(permissions)))
          entry.key: visibleInGroup(entry.key, permissions),
    };
  }
}
