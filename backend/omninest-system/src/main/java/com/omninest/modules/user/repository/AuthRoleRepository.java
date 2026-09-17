package com.omninest.modules.user.repository;

import com.omninest.modules.user.domain.AuthRole;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import jakarta.persistence.LockModeType;
import org.springframework.data.domain.Sort;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 认证角色仓储。
 *
 * @author OmniNest
 */
public interface AuthRoleRepository extends JpaRepository<AuthRole, UUID> {

    /**
     * 按编码查询角色。
     *
     * @param code 角色编码
     * @return 匹配角色
     */
    Optional<AuthRole> findByCode(String code);

    /**
     * 锁定并读取角色，用于串行化首次安装流程。
     *
     * @param code 角色编码
     * @return 匹配角色
     */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select role from AuthRole role where role.code = :code")
    Optional<AuthRole> findByCodeForUpdate(@Param("code") String code);

    /**
     * 加载全部角色并初始化权限集合（角色管理页）。
     *
     * <p>方法名不可被 Spring Data 解析为派生查询，必须显式 {@code @Query}。
     *
     * @param sort 排序
     * @return 角色列表
     */
    @EntityGraph(attributePaths = "permissions")
    @Query("select role from AuthRole role")
    List<AuthRole> findAllWithPermissions(Sort sort);

    /**
     * 批量查询角色对应的启用权限编码。
     *
     * @param roleIds 角色 ID 集合
     * @return (roleId, permissionCode) 行
     */
    @Query("""
            select role.id, permission.code
            from AuthRole role
            join role.permissions permission
            where role.id in :roleIds
              and role.enabled = true
              and permission.enabled = true
            """)
    List<Object[]> findPermissionCodeRowsByRoleIds(@Param("roleIds") Collection<UUID> roleIds);

    /**
     * 批量组装 roleId -> 权限编码集合。
     *
     * @param roleIds 角色 ID 集合
     * @return 角色 ID 到权限编码集合
     */
    default Map<UUID, Set<String>> findPermissionCodesByRoleIds(Collection<UUID> roleIds) {
        if (roleIds == null || roleIds.isEmpty()) {
            return Map.of();
        }
        return findPermissionCodeRowsByRoleIds(roleIds).stream()
                .collect(Collectors.groupingBy(
                        row -> (UUID) row[0],
                        LinkedHashMap::new,
                        Collectors.mapping(
                                row -> (String) row[1],
                                Collectors.toCollection(LinkedHashSet::new))));
    }
}
