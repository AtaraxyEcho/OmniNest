enum AdminSectionGroup {
  overview,
  operations,
  identity,
  configuration,
  storage,
}

enum AdminSection {
  overview(group: AdminSectionGroup.overview, pathSegment: 'overview'),
  analytics(group: AdminSectionGroup.overview, pathSegment: 'analytics'),
  monitoring(group: AdminSectionGroup.operations, pathSegment: 'monitoring'),
  logs(group: AdminSectionGroup.operations, pathSegment: 'logs'),
  tasks(group: AdminSectionGroup.operations, pathSegment: 'tasks'),
  sessions(group: AdminSectionGroup.operations, pathSegment: 'sessions'),
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
      AdminSection.overview ||
      AdminSection.analytics => {'system:config:read', 'system:user:read'},
      AdminSection.monitoring ||
      AdminSection.logs ||
      AdminSection.sessions ||
      AdminSection.config ||
      AdminSection.storage ||
      AdminSection.externalStorage => {'system:config:read'},
      AdminSection.tasks => {'task:admin'},
      AdminSection.users => {'system:user:read'},
      // 角色页同时依赖 /admin/roles 与 /admin/roles/detail
      AdminSection.roles => {'system:user:read', 'system:config:read'},
    };
  }

  bool isVisibleTo(Set<String> permissions) {
    return permissions.intersection(requiredAnyPermissions).isNotEmpty;
  }

  static AdminSection fromPathSegment(String? segment) {
    for (final section in values) {
      if (section.pathSegment == segment) {
        return section;
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
          entry.key: entry.value
              .where((section) => section.isVisibleTo(permissions))
              .toList(growable: false),
    };
  }
}
