package com.omninest.modules.user.repository;

import com.omninest.modules.user.domain.AuthBackupCode;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.transaction.annotation.Transactional;

/**
 * 两步验证备份码仓储。
 *
 * @author OmniNest
 */
public interface AuthBackupCodeRepository extends JpaRepository<AuthBackupCode, UUID> {

    /** 查询用户所有未使用的备份码。 */
    List<AuthBackupCode> findByUserIdAndUsedAtIsNull(UUID userId);

    /**
     * 原子核销一枚备份码：并发请求只有一个能把 used_at 从 NULL 改为时间。
     *
     * @param id 备份码 ID
     * @param now 核销时间
     * @return 实际更新行数，0 表示已被其他请求使用
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("update AuthBackupCode code set code.usedAt = :now "
            + "where code.id = :id and code.usedAt is null")
    int consume(@Param("id") UUID id, @Param("now") Instant now);

    /** 删除用户全部备份码。 */
    @Transactional(rollbackFor = Exception.class)
    @Modifying
    void deleteByUserId(UUID userId);
}
