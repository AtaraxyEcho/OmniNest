package com.omninest.modules.user.service;

import com.omninest.modules.user.domain.SessionRevocationEntity;
import com.omninest.modules.user.repository.ActiveSessionRepository;
import com.omninest.modules.user.repository.SessionRevocationJpaRepository;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * 会话吊销写库边界：始终以独立事务提交。
 *
 * <p>刷新令牌重放要“先吊销、再拒绝”，而拒绝本身要抛出运行时异常触发外层回滚。
 * 吊销记录与会话状态如果加入外层事务，就会随拒绝一起被撤销，只留下 Redis 黑名单；
 * 缓存淘汰后被盗会话即可复活。因此吊销必须走 {@code REQUIRES_NEW}，与外层成败解耦。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class SessionRevocationWriter {

    private final SessionRevocationJpaRepository revocationRepository;
    private final ActiveSessionRepository activeSessionRepository;

    /**
     * 在独立事务中写入撤销记录。
     *
     * @param userId 用户标识
     * @param sessionId 会话标识
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW, rollbackFor = Exception.class)
    public void persistRevocation(UUID userId, UUID sessionId) {
        revocationRepository.save(new SessionRevocationEntity(null, userId, sessionId, null));
    }

    /**
     * 在独立事务中写入撤销记录并标记会话已撤销。
     *
     * @param userId 用户标识
     * @param sessionId 会话标识
     * @param reason 撤销原因（写入会话行）
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW, rollbackFor = Exception.class)
    public void persistRevocationAndDeactivate(UUID userId, UUID sessionId, String reason) {
        revocationRepository.save(new SessionRevocationEntity(null, userId, sessionId, null));
        activeSessionRepository.revokeBySessionId(sessionId, reason);
    }
}
