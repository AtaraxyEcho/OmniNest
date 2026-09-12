package com.omninest.modules.user.repository;

import com.omninest.modules.user.domain.AuthTotpCredential;
import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
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

    /** 判断用户是否已确认启用两步验证。 */
    boolean existsByUserIdAndEnabledTrue(UUID userId);

    /** 删除用户全部 TOTP 凭据（含未确认）。 */
    @Transactional(rollbackFor = Exception.class)
    @Modifying
    void deleteByUserId(UUID userId);
}
