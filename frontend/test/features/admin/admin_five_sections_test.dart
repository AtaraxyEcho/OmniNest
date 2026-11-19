import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/admin/domain/admin_section.dart';

void main() {
  const allPermissions = <String>{
    'system:config:read',
    'system:user:read',
    'system:user:manage',
    'task:admin',
    'photo:admin',
    'media:library:manage',
  };

  test('导航只有 6 个分区，顺序与样例 Admin.tsx 一致', () {
    final primary = AdminSection.visiblePrimary(allPermissions);
    expect(primary, hasLength(6));
    expect(
      primary.map((section) => section.group).toList(),
      <AdminSectionGroup>[
        AdminSectionGroup.overview,
        AdminSectionGroup.identity,
        AdminSectionGroup.library,
        AdminSectionGroup.operations,
        AdminSectionGroup.configuration,
        AdminSectionGroup.storage,
      ],
    );
    for (final group in AdminSectionGroup.values) {
      expect(primary.singleWhere((s) => s.group == group), group.primary);
    }
  });

  test('旧的 10 个深链段仍是别名并落到原页签', () {
    for (final section in AdminSection.values) {
      expect(AdminSection.fromPathSegment(section.pathSegment), section);
    }
  });

  test('新的分组段落到对应分组的默认页签', () {
    for (final group in AdminSectionGroup.values) {
      final resolved = AdminSection.fromPathSegment(group.pathSegment);
      expect(resolved.group, group);
      expect(group.primary, isNotNull);
      expect(AdminSection.grouped[group], isNotEmpty);
    }
  });

  test('权限不足时只隐藏对应分区，不改变分区数量口径', () {
    final primary = AdminSection.visiblePrimary(<String>{'system:config:read'});
    for (final section in primary) {
      expect(
        AdminSection.visibleInGroup(section.group, <String>{
          'system:config:read',
        }),
        isNotEmpty,
      );
    }
    // tasks 需要 task:admin，不在该权限集里；ops 仍因日志/会话可见。
    expect(primary.any((s) => s.group == AdminSectionGroup.operations), isTrue);
  });
}
