package com.omninest.modules.user.repository;

import com.omninest.modules.user.domain.SessionRevocationEntity;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

/**
 * 会话撤销记录 JPA 仓储（Spring Data 自动实现）。
 */
public interface SessionRevocationJpaRepository extends JpaRepository<SessionRevocationEntity, UUID> {

    boolean existsByUserIdAndSessionId(UUID userId, UUID sessionId);

    /**
     * 删除用户全部会话撤销记录，供管理端物理删除空账户使用。
     *
     * @param userId 用户标识
     * @return 删除数量
     */
    @Modifying
    @Query("delete from SessionRevocationEntity revocation where revocation.userId = :userId")
    int deleteByUserId(@Param("userId") UUID userId);
}
