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
  /// 管理端按能力域收敛入口；后端仍以 @PreAuthorize 做最终校验。
  Set<String> get requiredAnyPermissions {
    return switch (this) {
      AdminSection.overview ||
      AdminSection.analytics ||
      AdminSection.monitoring => {
        'system:config:read',
        'system:user:read',
        'task:admin',
        'media:library:manage',
        'photo:admin',
      },
      AdminSection.logs ||
      AdminSection.sessions ||
      AdminSection.config ||
      AdminSection.storage => {'system:config:read'},
      AdminSection.tasks => {'task:admin'},
      AdminSection.users || AdminSection.roles => {'system:user:read'},
      AdminSection.externalStorage => {
        'system:config:read',
        'system:config:manage',
      },
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
