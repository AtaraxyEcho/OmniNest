package com.omninest.modules.user.repository;

import com.omninest.modules.user.domain.AuthUser;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
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

    /**
     * 只更新最近登录时间。
     *
     * <p>登录流程不再把游离用户实体整行 merge 回库：整行写回会用读取时的快照覆盖
     * 期间被管理员修改的状态、配额等列。</p>
     *
     * @param userId 用户标识
     * @param lastLoginAt 登录时间
     * @return 影响行数
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update AuthUser user set user.lastLoginAt = :lastLoginAt where user.id = :userId")
    int updateLastLoginAt(
            @Param("userId") UUID userId,
            @Param("lastLoginAt") Instant lastLoginAt);

    @Query("""
            select user from AuthUser user
            where user.status = :status
              and (:query = ''
                   or lower(user.username) like concat('%', :query, '%') escape '\\'
                   or lower(user.displayName) like concat('%', :query, '%') escape '\\')
            """)
    Page<AuthUser> searchByStatus(
            @Param("status") String status,
            @Param("query") String query,
            Pageable pageable
    );

    /**
     * 管理端用户列表搜索：用户名、展示名、邮箱小写模糊匹配，并按角色编码精确过滤。
     *
     * <p>角色过滤走 EXISTS 子查询而非 join：join 会把多角色用户的行集合裁剪成命中角色，
     * 页级权限映射随之为其他角色丢失权限；分页查询也不能对集合使用 EntityGraph，
     * 否则 Hibernate 只能把全部匹配行取回内存再分页。角色集合由
     * {@code hibernate.default_batch_fetch_size} 批量加载。</p>
     *
     * @param searchPattern 已小写化的模糊搜索模式，空字符串表示不限
     * @param roleCode 角色编码，空字符串表示不限
     * @param pageable 分页参数
     * @return 用户分页
     */
    @Query(value = """
            select user from AuthUser user
            where (:searchPattern = ''
                   or lower(user.username) like :searchPattern
                   or lower(user.displayName) like :searchPattern
                   or lower(user.email) like :searchPattern)
              and (:roleCode = ''
                   or exists (select role.id from user.roles role where role.code = :roleCode))
            """,
            countQuery = """
                    select count(user) from AuthUser user
                    where (:searchPattern = ''
                           or lower(user.username) like :searchPattern
                           or lower(user.displayName) like :searchPattern
                           or lower(user.email) like :searchPattern)
                      and (:roleCode = ''
                           or exists (select role.id from user.roles role where role.code = :roleCode))
                    """)
    Page<AuthUser> searchAdminUsers(
            @Param("searchPattern") String searchPattern,
            @Param("roleCode") String roleCode,
            Pageable pageable
    );

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
     * 一次按账号状态聚合用户数量，避免管理台多次 count。
     *
     * @return 状态到数量的映射行
     */
    @Query("select user.status, count(user) from AuthUser user group by user.status")
    List<Object[]> countUsersByStatus();

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
     * <p>配额为 0 或负数表示无限制，与 {@code RuntimeStorageQuotaPolicy} 的口径一致；
     * 无限额账户仍可原子累加预留，便于结算时按预留值回退。</p>
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
              AND (user.quotaBytes <= 0
                   OR user.usedBytes + user.reservedBytes + :bytes <= user.quotaBytes)
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
     * 推进用户访问令牌截止时间，只允许向前移动。
     *
     * @param userId 用户 ID
     * @param cutoff 新的截止时间
     * @return 成功更新时为 1，否则为 0
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            UPDATE AuthUser user
            SET user.accessCutoffAt = :cutoff,
                user.version = user.version + 1
            WHERE user.id = :userId
              AND (user.accessCutoffAt IS NULL OR user.accessCutoffAt < :cutoff)
            """)
    int advanceAccessCutoff(@Param("userId") UUID userId, @Param("cutoff") Instant cutoff);

    /**
     * 读取数据库中的访问令牌截止时间，供 Redis 缓存缺失时兜底。
     *
     * @param userId 用户 ID
     * @return 截止时间；从未发生权限变更时为空
     */
    @Query("select user.accessCutoffAt from AuthUser user where user.id = :userId")
    Optional<Instant> findAccessCutoffAt(@Param("userId") UUID userId);

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

    /**
     * 批量加载用户及其角色。
     *
     * <p>管理台批量调额、对账等场景必须在一次查询内取回角色集合，否则每个目标用户都会
     * 触发一次角色 JOIN 查询，形成 N+1。</p>
     *
     * @param ids 用户 ID 集合
     * @return 用户列表
     */
    @EntityGraph(attributePaths = "roles")
    @Query("select user from AuthUser user where user.id in :ids")
    List<AuthUser> findAllWithRolesByIdIn(@Param("ids") Collection<UUID> ids);

    /**
     * 查询一组用户中持有指定角色编码的用户 ID。
     *
     * <p>配额端口需要判断“目标是否为管理员”，但不应把角色实体暴露给配额模块。</p>
     *
     * @param ids 用户 ID 集合
     * @param roleCodes 角色编码集合
     * @return 持有任一角色编码的用户 ID
     */
    @Query("select distinct user.id from AuthUser user join user.roles role "
            + "where user.id in :ids and role.code in :roleCodes")
    List<UUID> findIdsHavingAnyRole(
            @Param("ids") Collection<UUID> ids,
            @Param("roleCodes") Collection<String> roleCodes);

    /**
     * 批量设置存储配额。
     *
     * <p>逐户 {@code save} 会把整行实体写回，覆盖对账窗口内并发修改的密码、昵称等列；
     * 单条 UPDATE 只改配额列，并自增版本号以让其他会话的乐观锁失效。</p>
     *
     * @param userIds 目标用户 ID 集合
     * @param quotaBytes 新配额字节数
     * @return 更新的行数
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            UPDATE AuthUser user
            SET user.quotaBytes = :quotaBytes,
                user.version = user.version + 1
            WHERE user.id IN :userIds
            """)
    int updateQuotaBatch(
            @Param("userIds") Collection<UUID> userIds,
            @Param("quotaBytes") long quotaBytes);

    /**
     * 按实际用量校准单个用户的已使用字节。
     *
     * <p>只改 {@code used_bytes} 一列：对账把整批实体 {@code saveAll} 回库时会用读取时的
     * 快照覆盖并发修改的密码、昵称，并可能与文件写入的原子增量互相覆盖。</p>
     *
     * @param userId 用户 ID
     * @param actualBytes 实际用量字节数
     * @return 发生变更时为 1，无需变更时为 0
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            UPDATE AuthUser user
            SET user.usedBytes = :actualBytes,
                user.version = user.version + 1
            WHERE user.id = :userId
              AND user.usedBytes <> :actualBytes
            """)
    int reconcileUsedBytes(
            @Param("userId") UUID userId,
            @Param("actualBytes") long actualBytes);
}
