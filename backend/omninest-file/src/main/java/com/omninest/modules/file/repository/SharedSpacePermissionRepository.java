package com.omninest.modules.file.repository;

import com.omninest.modules.file.domain.SharedSpacePermission;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface SharedSpacePermissionRepository extends JpaRepository<SharedSpacePermission, UUID> {
    Optional<SharedSpacePermission> findByRoleId(UUID roleId);

    /**
     * 删除角色对应的共享空间权限行；角色删除后不留孤儿数据。
     */
    void deleteByRoleId(UUID roleId);

    /**
     * 批量查询角色权限（避免 N+1）。
     */
    List<SharedSpacePermission> findByRoleIdIn(Collection<UUID> roleIds);
}
