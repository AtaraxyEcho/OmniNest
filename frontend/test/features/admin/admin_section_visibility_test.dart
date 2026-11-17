import 'package:flutter_test/flutter_test.dart';
import 'package:omninest/features/admin/domain/admin_section.dart';

void main() {
  test('任务分区仅对 task:admin 可见', () {
    expect(AdminSection.tasks.isVisibleTo({'task:read'}), isFalse);
    expect(AdminSection.tasks.isVisibleTo({'task:admin'}), isTrue);
  });

  test('角色分区接受 user:read 或 config:read', () {
    expect(AdminSection.roles.isVisibleTo({'system:user:read'}), isTrue);
    expect(AdminSection.roles.isVisibleTo({'system:config:read'}), isTrue);
    expect(AdminSection.roles.isVisibleTo({'task:admin'}), isFalse);
  });

  test('维护分区接受分享、照片或媒体库任一管理权限', () {
    expect(
      AdminSection.maintenance.isVisibleTo({'system:user:manage'}),
      isTrue,
    );
    expect(AdminSection.maintenance.isVisibleTo({'photo:admin'}), isTrue);
    expect(
      AdminSection.maintenance.isVisibleTo({'media:library:manage'}),
      isTrue,
    );
    expect(
      AdminSection.maintenance.isVisibleTo({'system:config:read'}),
      isFalse,
    );
  });

  test('成员权限集不可打开任何管理分区', () {
    final member = {
      'profile:read',
      'profile:write',
      'file:read',
      'file:write',
      'media:read',
      'media:write',
      'photo:read',
      'photo:write',
      'task:read',
      'backdrop:read',
      'backdrop:write',
    };
    for (final section in AdminSection.values) {
      expect(
        section.isVisibleTo(member),
        isFalse,
        reason: '${section.name} 不应对 MEMBER 开放',
      );
    }
  });
}
