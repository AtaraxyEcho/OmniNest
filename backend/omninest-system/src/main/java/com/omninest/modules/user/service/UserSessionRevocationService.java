package com.omninest.modules.user.service;

import com.omninest.modules.user.domain.AuthActiveSession;
import com.omninest.modules.user.repository.ActiveSessionRepository;
import java.time.Duration;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

/**
 * 批量撤销用户会话，并在业务事务提交后发布撤销结果。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class UserSessionRevocationService {

    private static final Duration REVOCATION_TTL = Duration.ofDays(30);

    private final ActiveSessionRepository activeSessionRepository;
    private final SessionRevocationService sessionRevocationService;

    /**
     * 撤销指定用户集合的全部活跃会话。
     *
     * @param userIds 用户标识集合
     * @param reason  撤销原因
     */
    @Transactional(rollbackFor = Exception.class)
    public void revokeAll(Collection<UUID> userIds, String reason) {
        if (userIds == null || userIds.isEmpty()) {
            return;
        }
        List<AuthActiveSession> sessions = activeSessionRepository.findByUserIdInAndRevokedAtIsNull(userIds);
        if (sessions.isEmpty()) {
            return;
        }
        activeSessionRepository.revokeByUserIdIn(userIds, reason);
        Map<UUID, List<UUID>> sessionsByUser = sessions.stream().collect(Collectors.groupingBy(
                AuthActiveSession::getUserId,
                Collectors.mapping(AuthActiveSession::getId, Collectors.toList())
        ));
        sessionsByUser.forEach(sessionRevocationService::recordRevocations);
        registerAfterCommit(sessionsByUser);
    }

    /**
     * 撤销指定用户除保留会话外的全部活跃会话，供修改密码等自助操作保留当前登录态。
     *
     * @param userId        用户标识
     * @param keepSessionId 需要保留的当前会话 ID；为 null 时等价于撤销全部会话
     * @param reason        撤销原因
     */
    @Transactional(rollbackFor = Exception.class)
    public void revokeAllExcept(UUID userId, UUID keepSessionId, String reason) {
        List<AuthActiveSession> sessions = activeSessionRepository
                .findByUserIdAndRevokedAtIsNullOrderByCreatedAtDesc(userId);
        List<UUID> sessionIds = sessions.stream()
                .map(AuthActiveSession::getId)
                .filter(sessionId -> keepSessionId == null || !sessionId.equals(keepSessionId))
                .toList();
        if (sessionIds.isEmpty()) {
            return;
        }
        if (keepSessionId == null) {
            activeSessionRepository.revokeByUserIdIn(List.of(userId), reason);
        } else {
            activeSessionRepository.revokeByUserIdExcluding(userId, keepSessionId, reason);
        }
        sessionRevocationService.recordRevocations(userId, sessionIds);
        registerAfterCommit(Map.of(userId, sessionIds));
    }

    private void registerAfterCommit(Map<UUID, List<UUID>> sessionsByUser) {
        if (!TransactionSynchronizationManager.isSynchronizationActive()) {
            writeBlacklist(sessionsByUser);
            return;
        }
        TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
            @Override
            public void afterCommit() {
                writeBlacklist(sessionsByUser);
            }
        });
    }

    private void writeBlacklist(Map<UUID, List<UUID>> sessionsByUser) {
        sessionsByUser.forEach((userId, sessionIds) ->
                sessionRevocationService.publishRevocations(userId, sessionIds, REVOCATION_TTL));
    }
}
