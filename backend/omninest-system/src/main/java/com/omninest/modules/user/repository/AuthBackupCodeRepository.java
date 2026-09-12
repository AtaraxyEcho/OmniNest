package com.omninest.modules.user.repository;

import com.omninest.modules.user.domain.AuthBackupCode;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.transaction.annotation.Transactional;

/**
 * 两步验证备份码仓储。
 *
 * @author OmniNest
 */
public interface AuthBackupCodeRepository extends JpaRepository<AuthBackupCode, UUID> {

    /** 查询用户所有未使用的备份码。 */
    List<AuthBackupCode> findByUserIdAndUsedAtIsNull(UUID userId);

    /** 删除用户全部备份码。 */
    @Transactional(rollbackFor = Exception.class)
    @Modifying
    void deleteByUserId(UUID userId);
}
