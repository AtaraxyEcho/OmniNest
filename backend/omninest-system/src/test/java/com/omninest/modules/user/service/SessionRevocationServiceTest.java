package com.omninest.modules.user.service;

import com.omninest.common.security.SessionRevocationCache;
import com.omninest.modules.user.domain.SessionRevocationEntity;
import com.omninest.modules.user.repository.SessionRevocationJpaRepository;
import java.time.Duration;
import java.util.List;
import java.util.UUID;
import java.util.function.Consumer;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * 会话撤销业务服务测试。
 *
 * @author OmniNest
 */
class SessionRevocationServiceTest {

    private SessionRevocationJpaRepository repository;
    private SessionRevocationCache cache;
    private TransactionTemplate transactionTemplate;
    private SessionRevocationService service;

    @SuppressWarnings("unchecked")
    @BeforeEach
    void setUp() {
        repository = Mockito.mock(SessionRevocationJpaRepository.class);
        cache = Mockito.mock(SessionRevocationCache.class);
        transactionTemplate = Mockito.mock(TransactionTemplate.class);
        Mockito.doAnswer(invocation -> {
            invocation.getArgument(0, Consumer.class).accept(null);
            return null;
        }).when(transactionTemplate).executeWithoutResult(Mockito.any());
        service = new SessionRevocationService(repository, cache, transactionTemplate);
    }

    @Test
    void cachedRevocationSkipsDatabaseLookup() {
        UUID userId = UUID.randomUUID();
        UUID sessionId = UUID.randomUUID();
        Mockito.when(cache.contains(userId, sessionId)).thenReturn(true);

        boolean result = service.isRevoked(userId, sessionId);

        Assertions.assertThat(result).isTrue();
        Mockito.verifyNoInteractions(repository);
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

        ArgumentCaptor<SessionRevocationEntity> captor = ArgumentCaptor.forClass(SessionRevocationEntity.class);
        Mockito.verify(repository).save(captor.capture());
        Assertions.assertThat(captor.getValue().getUserId()).isEqualTo(userId);
        Assertions.assertThat(captor.getValue().getSessionId()).isEqualTo(sessionId);
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
