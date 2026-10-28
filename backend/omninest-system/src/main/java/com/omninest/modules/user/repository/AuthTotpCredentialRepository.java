package com.omninest.modules.user.repository;

import com.omninest.modules.user.domain.AuthTotpCredential;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

/**
 * 两步验证 TOTP 凭据仓储。
 *
 * @author OmniNest
 */
public interface AuthTotpCredentialRepository extends JpaRepository<AuthTotpCredential, UUID> {

    /** 查询用户的 TOTP 凭据（含未确认的待启用凭据）。 */
    Optional<AuthTotpCredential> findByUserId(UUID userId);

    /** 查询用户已确认启用的 TOTP 凭据。 */
    Optional<AuthTotpCredential> findByUserIdAndEnabledTrue(UUID userId);

    /** 批量查询一组用户已确认启用的 TOTP 凭据（管理用户列表两步验证状态）。 */
    List<AuthTotpCredential> findByUserIdInAndEnabledTrue(Collection<UUID> userIds);

    /** 判断用户是否已确认启用两步验证。 */
    boolean existsByUserIdAndEnabledTrue(UUID userId);

    /** 删除用户全部 TOTP 凭据（含未确认）。 */
    @Transactional(rollbackFor = Exception.class)
    @Modifying
    void deleteByUserId(UUID userId);

    /**
     * 原子消费一个 TOTP 时间步。
     *
     * <p>并发提交同一时间窗口的验证码时，只有第一个请求能把 {@code lastUsedStep}
     * 推进到该步；其余请求返回 0，按验证码已使用拒绝。依赖乐观锁兜底只会把
     * 冲突翻译成未映射的 5xx。</p>
     *
     * @param userId 用户标识
     * @param step 已匹配的时间步
     * @param now 更新时间
     * @return 更新行数，0 表示该步已被其他请求消费
     */
    @Transactional(rollbackFor = Exception.class)
    @Modifying
    @Query("update AuthTotpCredential c set c.lastUsedStep = :step, c.updatedAt = :now, "
            + "c.version = c.version + 1 where c.userId = :userId and c.enabled = true "
            + "and (c.lastUsedStep is null or c.lastUsedStep < :step)")
    int consumeStep(
            @Param("userId") UUID userId,
            @Param("step") long step,
            @Param("now") Instant now);
}
