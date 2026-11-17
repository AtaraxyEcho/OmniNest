package com.omninest.modules.user.security;

import com.omninest.common.security.ActiveSessionFallbackLookup;
import com.omninest.modules.user.domain.AuthActiveSession;
import com.omninest.modules.user.repository.ActiveSessionRepository;
import java.time.Instant;
import java.util.Comparator;
import java.util.Optional;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/**
 * 基于会话仓储的活动会话回退查询。
 *
 * <p>Redis 注册表故障时的同平台互斥兜底：查询未撤销、未过期会话中最近活跃的一个。
 *
 * @author OmniNest
 */
@Component
@RequiredArgsConstructor
public class ActiveSessionRepositoryFallbackLookup implements ActiveSessionFallbackLookup {

    private final ActiveSessionRepository activeSessionRepository;

    @Override
    public Optional<UUID> findActiveSessionId(UUID userId, String platform) {
        Instant now = Instant.now();
        return activeSessionRepository.findByUserIdAndClientPlatformAndRevokedAtIsNull(userId, platform)
                .stream()
                .filter(session -> session.getExpiresAt() != null && session.getExpiresAt().isAfter(now))
                .max(Comparator.comparing(
                        AuthActiveSession::getLastActiveAt,
                        Comparator.nullsFirst(Comparator.naturalOrder())
                ))
                .map(AuthActiveSession::getId);
    }
}
