package com.omninest.modules.user.service;

import com.omninest.common.security.SessionRevocationCache;
import com.omninest.modules.user.domain.SessionRevocationEntity;
import com.omninest.modules.user.repository.SessionRevocationJpaRepository;
import java.time.Duration;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;

/**
 * 会话撤销业务服务测试。
 *
 * @author OmniNest
 */
class SessionRevocationServiceTest {

    private SessionRevocationJpaRepository repository;
    private SessionRevocationCache cache;
    private SessionRevocationWriter writer;
    private SessionRevocationService service;

    @BeforeEach
    void setUp() {
        repository = Mockito.mock(SessionRevocationJpaRepository.class);
        cache = Mockito.mock(SessionRevocationCache.class);
        writer = Mockito.mock(SessionRevocationWriter.class);
        service = new SessionRevocationService(repository, cache, writer);
    }

    @Test
    void cachedRevocationSkipsDatabaseLookup() {
        UUID userId = UUID.randomUUID();
        UUID sessionId = UUID.randomUUID();
        Mockito.when(cache.checkRevoked(userId, sessionId)).thenReturn(Optional.of(true));

        boolean result = service.isRevoked(userId, sessionId);

        Assertions.assertThat(result).isTrue();
        Mockito.verifyNoInteractions(repository);
    }

    @Test
    void cacheConfirmedCleanSessionSkipsDatabaseLookup() {
        // 正常流量下绝大多数会话都未撤销：缓存确认未撤销时必须直接放行，
        // 否则每个请求都要额外查一次数据库，黑名单缓存退化成第二次往返。
        UUID userId = UUID.randomUUID();
        UUID sessionId = UUID.randomUUID();
        Mockito.when(cache.checkRevoked(userId, sessionId)).thenReturn(Optional.of(false));

        boolean result = service.isRevoked(userId, sessionId);

        Assertions.assertThat(result).isFalse();
        Mockito.verifyNoInteractions(repository);
    }

    @Test
    void databaseConfirmedCleanSessionWritesShortLivedNotRevokedMarker() {
        UUID userId = UUID.randomUUID();
        UUID sessionId = UUID.randomUUID();
        Mockito.when(cache.checkRevoked(userId, sessionId)).thenReturn(Optional.empty());
        Mockito.when(repository.existsByUserIdAndSessionId(userId, sessionId)).thenReturn(false);

        boolean result = service.isRevoked(userId, sessionId);

        Assertions.assertThat(result).isFalse();
        Mockito.verify(cache).markNotRevoked(
                Mockito.eq(userId), Mockito.eq(sessionId), Mockito.any(Duration.class));
    }

    @Test
    void cacheMissFallsBackToDatabaseAndWarmsCache() {
        UUID userId = UUID.randomUUID();
        UUID sessionId = UUID.randomUUID();
        Mockito.when(repository.existsByUserIdAndSessionId(userId, sessionId)).thenReturn(true);

        boolean result = service.isRevoked(userId, sessionId);

        Assertions.assertThat(result).isTrue();
        Mockito.verify(cache).markRevoked(userId, List.of(sessionId), Duration.ofDays(30));
    }

    @Test
    void databaseFailureRejectsCurrentSession() {
        Mockito.when(repository.existsByUserIdAndSessionId(Mockito.any(), Mockito.any()))
                .thenThrow(new IllegalStateException("Database unavailable"));

        boolean result = service.isRevoked(UUID.randomUUID(), UUID.randomUUID());

        Assertions.assertThat(result).isTrue();
    }

    @Test
    void revokeSessionPersistsAndPublishesRevocation() {
        UUID userId = UUID.randomUUID();
        UUID sessionId = UUID.randomUUID();
        Duration ttl = Duration.ofDays(30);

        service.revokeSession(userId, sessionId, ttl);

        Mockito.verify(writer).persistRevocation(userId, sessionId);
        Mockito.verify(cache).markRevoked(userId, List.of(sessionId), ttl);
    }

    @Test
    void revokeSessionAndDeactivateWritesBothRowsThroughIndependentWriter() {
        UUID userId = UUID.randomUUID();
        UUID sessionId = UUID.randomUUID();
        Duration ttl = Duration.ofDays(30);

        service.revokeSessionAndDeactivate(userId, sessionId, "刷新令牌重放，会话已撤销", ttl);

        Mockito.verify(writer).persistRevocationAndDeactivate(userId, sessionId, "刷新令牌重放，会话已撤销");
        Mockito.verify(cache).markRevoked(userId, List.of(sessionId), ttl);
    }

    @Test
    void recordRevocationsUsesOneDatabaseBatch() {
        UUID userId = UUID.randomUUID();
        UUID firstSessionId = UUID.randomUUID();
        UUID secondSessionId = UUID.randomUUID();

        service.recordRevocations(userId, List.of(firstSessionId, secondSessionId));

        ArgumentCaptor<List<SessionRevocationEntity>> captor = ArgumentCaptor.captor();
        Mockito.verify(repository).saveAll(captor.capture());
        Assertions.assertThat(captor.getValue())
                .extracting(SessionRevocationEntity::getSessionId)
                .containsExactly(firstSessionId, secondSessionId);
    }
}
