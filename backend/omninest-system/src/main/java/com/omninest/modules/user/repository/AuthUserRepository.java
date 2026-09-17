package com.omninest.modules.user.repository;

import com.omninest.modules.user.domain.AuthUser;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 认证用户仓储。
 *
 * @author OmniNest
 */
public interface AuthUserRepository extends JpaRepository<AuthUser, UUID> {

    @EntityGraph(attributePaths = "roles")
    Optional<AuthUser> findByUsername(String username);

    @EntityGraph(attributePaths = {"roles", "roles.permissions"})
    @Query("select user from AuthUser user where user.username = :username")
    Optional<AuthUser> findByUsernameWithPermissions(@Param("username") String username);

    @EntityGraph(attributePaths = "roles")
    Optional<AuthUser> findWithRolesById(UUID id);

    @EntityGraph(attributePaths = {"roles", "roles.permissions"})
    @Query("select user from AuthUser user where user.id = :id")
    Optional<AuthUser> findWithRolesAndPermissionsById(@Param("id") UUID id);

    @Query("""
            select user from AuthUser user
            where user.status = :status
              and (:query = ''
                   or lower(user.username) like concat('%', :query, '%')
                   or lower(coalesce(user.displayName, '')) like concat('%', :query, '%'))
            """)
    Page<AuthUser> searchByStatus(
            @Param("status") String status,
            @Param("query") String query,
            Pageable pageable
    );

    @EntityGraph(attributePaths = "roles")
    @Override
    List<AuthUser> findAll(Sort sort);

    @EntityGraph(attributePaths = "roles")
    @Override
    Page<AuthUser> findAll(Pageable pageable);

    boolean existsByUsername(String username);

    boolean existsByRoles_Code(String roleCode);

    List<AuthUser> findAllByRoles_Code(String roleCode);

    /**
     * 统计指定状态的用户数量。
     *
     * @param status 用户状态
     * @return 用户数量
     */
    long countByStatus(String status);

    /**
     * 按启用角色统计用户数量。
     *
     * @return 角色编码和用户数量投影
     */
    @Query("""
            select role.code, count(distinct authUser.id)
            from AuthUser authUser
            join authUser.roles role
            where role.enabled = true
            group by role.code
            """)
    List<Object[]> countUsersByEnabledRole();

    /**
     * 查询拥有指定权限且状态匹配的用户。
     *
     * @param permissionCode 权限编码
     * @param status 用户状态
     * @return 匹配用户列表
     */
    List<AuthUser> findDistinctByRoles_Permissions_CodeAndStatus(String permissionCode, String status);

    /**
     * 查询首批用户标识。
     *
     * @param limit 批次上限
     * @return 按标识升序排列的用户标识
     */
    @Query(value = """
            SELECT auth_user.id
            FROM omni.auth_users auth_user
            ORDER BY auth_user.id ASC
            LIMIT :limit
            """, nativeQuery = true)
    List<UUID> findFirstUserIds(@Param("limit") int limit);

    /**
     * 查询指定游标后的用户标识。
     *
     * @param cursor 排他游标
     * @param limit 批次上限
     * @return 按标识升序排列的用户标识
     */
    @Query(value = """
            SELECT auth_user.id
            FROM omni.auth_users auth_user
            WHERE auth_user.id > :cursor
            ORDER BY auth_user.id ASC
            LIMIT :limit
            """, nativeQuery = true)
    List<UUID> findUserIdsAfter(@Param("cursor") UUID cursor, @Param("limit") int limit);

    /**
     * 查询仍被用户资料引用的头像文件标识。
     *
     * @param avatarFileIds 候选头像文件标识
     * @return 已引用头像文件标识
     */
    @Query("""
            select authUser.avatarFileId
            from AuthUser authUser
            where authUser.avatarFileId in :avatarFileIds
            """)
    List<UUID> findExistingAvatarFileIds(@Param("avatarFileIds") Collection<UUID> avatarFileIds);

    /**
     * 在剩余配额足够时原子增加预留字节数。
     *
     * @param userId 用户 ID
     * @param bytes 预留字节数
     * @return 成功更新时为 1，否则为 0
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            UPDATE AuthUser user
            SET user.reservedBytes = user.reservedBytes + :bytes,
                user.version = user.version + 1
            WHERE user.id = :userId
              AND user.usedBytes + user.reservedBytes + :bytes <= user.quotaBytes
            """)
    int reserveStorage(@Param("userId") UUID userId, @Param("bytes") long bytes);

    /**
     * 将预留配额原子结算为实际用量。
     *
     * @param userId 用户 ID
     * @param reservedBytes 原预留字节数
     * @param committedBytes 实际写入字节数
     * @return 成功更新时为 1，否则为 0
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            UPDATE AuthUser user
            SET user.reservedBytes = user.reservedBytes - :reservedBytes,
                user.usedBytes = user.usedBytes + :committedBytes,
                user.version = user.version + 1
            WHERE user.id = :userId
              AND user.reservedBytes >= :reservedBytes
            """)
    int settleStorageReservation(
            @Param("userId") UUID userId,
            @Param("reservedBytes") long reservedBytes,
            @Param("committedBytes") long committedBytes
    );

    /**
     * 为不受配额限制的账户原子增加实际用量。
     *
     * @param userId 用户 ID
     * @param bytes 增加字节数
     * @return 成功更新时为 1，否则为 0
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            UPDATE AuthUser user
            SET user.usedBytes = user.usedBytes + :bytes,
                user.version = user.version + 1
            WHERE user.id = :userId
            """)
    int incrementUsageAtomic(@Param("userId") UUID userId, @Param("bytes") long bytes);

    /**
     * 原子减少实际用量并保证结果不小于零。
     *
     * @param userId 用户 ID
     * @param bytes 减少字节数
     * @return 成功更新时为 1，否则为 0
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            UPDATE AuthUser user
            SET user.usedBytes = CASE
                    WHEN user.usedBytes > :bytes THEN user.usedBytes - :bytes
                    ELSE 0
                END,
                user.version = user.version + 1
            WHERE user.id = :userId
            """)
    int decrementUsageAtomic(@Param("userId") UUID userId, @Param("bytes") long bytes);
}
