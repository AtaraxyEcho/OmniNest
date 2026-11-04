package com.omninest.modules.user.service;

import com.omninest.common.security.AuthenticationTokenPolicy;
import com.omninest.common.security.SessionRevocationCache;
import com.omninest.modules.user.domain.SessionRevocationEntity;
import com.omninest.modules.user.repository.AuthUserRepository;
import com.omninest.modules.user.repository.SessionRevocationJpaRepository;
import java.time.Duration;
import java.time.Instant;
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
    private AuthenticationTokenPolicy authenticationTokenPolicy;
    private AuthUserRepository authUserRepository;
    private SessionRevocationService service;

    @BeforeEach
    void setUp() {
        repository = Mockito.mock(SessionRevocationJpaRepository.class);
        cache = Mockito.mock(SessionRevocationCache.class);
        writer = Mockito.mock(SessionRevocationWriter.class);
        authenticationTokenPolicy = Mockito.mock(AuthenticationTokenPolicy.class);
        authUserRepository = Mockito.mock(AuthUserRepository.class);
        Mockito.when(authenticationTokenPolicy.accessTokenTtl()).thenReturn(Duration.ofMinutes(30));
        service = new SessionRevocationService(
                repository, cache, writer, authenticationTokenPolicy, authUserRepository);
    }

    @Test
    void tokenIssuedBeforeOrAtPermissionCutoffIsStale() {
        UUID userId = UUID.randomUUID();
        Instant cutoff = Instant.parse("2026-11-02T10:00:00Z");
        Mockito.when(cache.accessTokenCutoff(userId)).thenReturn(Optional.of(cutoff));

        Assertions.assertThat(service.isTokenStale(userId, cutoff.minusSeconds(1))).isTrue();
        // 同一秒内签发的令牌必须失效：秒级严格小于会把撤权同秒的旧权限令牌放行。
        Assertions.assertThat(service.isTokenStale(userId, cutoff)).isTrue();
        Assertions.assertThat(service.isTokenStale(userId, cutoff.plusSeconds(1))).isFalse();
        Assertions.assertThat(service.isTokenStale(userId, null)).isTrue();
    }

    @Test
    void databaseCutoffBacksUpMissingCacheEntry() {
        UUID userId = UUID.randomUUID();
        Instant cutoff = Instant.parse("2026-11-02T10:00:00Z");
        Mockito.when(cache.accessTokenCutoff(userId)).thenReturn(Optional.empty());
        Mockito.when(authUserRepository.findAccessCutoffAt(userId)).thenReturn(Optional.of(cutoff));

        Assertions.assertThat(service.isTokenStale(userId, cutoff.minusSeconds(1))).isTrue();
        // 回源结果写回缓存，不必每个请求都查库。
        Mockito.verify(cache).markAccessTokenCutoff(userId, cutoff, Duration.ofMinutes(30));
    }

    @Test
    void invalidateAccessTokensWritesDatabaseAndCache() {
        UUID userId = UUID.randomUUID();
        Instant cutoff = Instant.now();

        service.invalidateAccessTokensBefore(userId, cutoff);

        Mockito.verify(writer).persistAccessCutoff(userId, cutoff);
        Mockito.verify(cache).markAccessTokenCutoff(
                userId, cutoff, Duration.ofMinutes(30));
    }

    @Test
    void redisFailureDoesNotRollbackDatabaseCutoff() {
        UUID userId = UUID.randomUUID();
        Instant cutoff = Instant.now();
        Mockito.doThrow(new IllegalStateException("Redis down"))
                .when(cache).markAccessTokenCutoff(userId, cutoff, Duration.ofMinutes(30));

        service.invalidateAccessTokensBefore(userId, cutoff);

        // 数据库列是权威兜底：Redis 写失败只能降级告警，不能让事务回滚已提交的截止时间。
        Mockito.verify(writer).persistAccessCutoff(userId, cutoff);
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
