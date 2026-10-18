package com.omninest.modules.sync.realtime;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.security.SessionRevocationChecker;
import com.omninest.modules.sync.config.SyncEventProperties;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.stream.IntStream;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.web.socket.CloseStatus;
import org.springframework.web.socket.WebSocketHandler;
import org.springframework.web.socket.WebSocketMessage;
import org.springframework.web.socket.WebSocketSession;

/**
 * 原始 WebSocket 会话注册表单元测试。
 *
 * @author OmniNest
 */
class RealtimeWebSocketSessionRegistryTest {

    private final SessionRevocationChecker revocationChecker = Mockito.mock(SessionRevocationChecker.class);
    private final SyncEventProperties properties = new SyncEventProperties();
    private final SimpleMeterRegistry meterRegistry = new SimpleMeterRegistry();
    private final RealtimeWebSocketSessionRegistry registry = new RealtimeWebSocketSessionRegistry(
            revocationChecker,
            properties,
            meterRegistry
    );

    @Test
    void auditClosesRevokedAuthorizedSession() throws Exception {
        UUID userId = UUID.randomUUID();
        UUID sid = UUID.randomUUID();
        WebSocketSession session = Mockito.mock(WebSocketSession.class);
        Mockito.when(session.getId()).thenReturn("session-1");
        Mockito.when(session.isOpen()).thenReturn(true);
        WebSocketHandler handler = Mockito.mock(WebSocketHandler.class);
        registry.decorate(handler).afterConnectionEstablished(session);
        registry.authorize("session-1", userId, sid, Instant.now().plusSeconds(600));
        Mockito.when(revocationChecker.isRevoked(userId, sid)).thenReturn(true);

        registry.closeInvalidSessions();

        Mockito.verify(session).close(CloseStatus.POLICY_VIOLATION);
    }

    @Test
    void authorizeRejectsUnknownTransportSession() {
        assertThatThrownBy(() -> registry.authorize(
                "missing-session",
                UUID.randomUUID(),
                UUID.randomUUID(),
                Instant.now().plusSeconds(600)
        )).isInstanceOf(RealtimeAuthenticationException.class)
                .hasMessageContaining("不存在");
    }

    @Test
    void authorizeRejectsClosedTransportSession() throws Exception {
        WebSocketSession session = session("closed-session");
        WebSocketHandler handler = Mockito.mock(WebSocketHandler.class);
        WebSocketHandler decorated = registry.decorate(handler);
        decorated.afterConnectionEstablished(session);
        decorated.afterConnectionClosed(session, CloseStatus.NORMAL);

        assertThatThrownBy(() -> registry.authorize(
                "closed-session",
                UUID.randomUUID(),
                UUID.randomUUID(),
                Instant.now().plusSeconds(600)
        )).isInstanceOf(RealtimeAuthenticationException.class)
                .hasMessageContaining("不存在");
    }

    @Test
    void rejectsConnectionAboveInstanceCapacityAndReleasesSlotAfterClose() throws Exception {
        properties.getRealtime().setMaxSessionsPerInstance(1);
        registry.registerMetrics();
        WebSocketSession firstSession = session("session-1");
        WebSocketSession rejectedSession = session("session-2");
        WebSocketSession replacementSession = session("session-3");
        WebSocketHandler handler = Mockito.mock(WebSocketHandler.class);
        WebSocketHandler decorated = registry.decorate(handler);

        decorated.afterConnectionEstablished(firstSession);
        decorated.afterConnectionEstablished(rejectedSession);

        Mockito.verify(handler).afterConnectionEstablished(firstSession);
        Mockito.verify(handler, Mockito.never()).afterConnectionEstablished(rejectedSession);
        Mockito.verify(rejectedSession).close(Mockito.argThat(status -> status.getCode() == 1013));
        assertThat(
                meterRegistry.get("omninest.sync.realtime.sessions.active").gauge().value()
        ).isEqualTo(1D);
        assertThat(
                meterRegistry.get("omninest.sync.realtime.sessions.rejected")
                        .tag("reason", "capacity")
                        .counter()
                        .count()
        ).isEqualTo(1D);

        decorated.afterConnectionClosed(firstSession, CloseStatus.NORMAL);
        decorated.afterConnectionEstablished(replacementSession);

        Mockito.verify(handler).afterConnectionEstablished(replacementSession);
        assertThat(
                meterRegistry.get("omninest.sync.realtime.sessions.active").gauge().value()
        ).isEqualTo(1D);
    }

    @Test
    void releasesCapacityWhenConnectionHandlerFails() throws Exception {
        properties.getRealtime().setMaxSessionsPerInstance(1);
        WebSocketSession failedSession = session("session-failed");
        WebSocketHandler failingHandler = Mockito.mock(WebSocketHandler.class);
        Mockito.doThrow(new IllegalStateException("连接初始化失败"))
                .when(failingHandler)
                .afterConnectionEstablished(failedSession);

        assertThatThrownBy(() -> registry.decorate(failingHandler).afterConnectionEstablished(failedSession))
                .isInstanceOf(IllegalStateException.class);

        WebSocketSession replacementSession = session("session-replacement");
        WebSocketHandler replacementHandler = Mockito.mock(WebSocketHandler.class);
        registry.decorate(replacementHandler).afterConnectionEstablished(replacementSession);

        Mockito.verify(replacementHandler).afterConnectionEstablished(replacementSession);
    }

    @Test
    void concurrentConnectionWavesNeverExceedCapacityAndReleaseAllSlots() throws Exception {
        int capacity = 32;
        int connectionsPerWave = 256;
        int waveCount = 8;
        properties.getRealtime().setMaxSessionsPerInstance(capacity);
        registry.registerMetrics();
        AtomicInteger acceptedConnections = new AtomicInteger();
        WebSocketHandler handler = Mockito.mock(WebSocketHandler.class);
        Mockito.doAnswer(invocation -> {
            acceptedConnections.incrementAndGet();
            return null;
        }).when(handler).afterConnectionEstablished(Mockito.any(WebSocketSession.class));
        WebSocketHandler decorated = registry.decorate(handler);

        try (ExecutorService executor = Executors.newFixedThreadPool(64)) {
            for (int wave = 0; wave < waveCount; wave++) {
                int waveNumber = wave;
                List<WebSocketSession> sessions = IntStream.range(0, connectionsPerWave)
                        .mapToObj(index -> session("wave-" + waveNumber + "-session-" + index))
                        .toList();

                runConcurrently(executor, sessions, decorated::afterConnectionEstablished);

                assertThat(activeSessionCount()).isEqualTo(capacity);
                assertThat(acceptedConnections).hasValue((wave + 1) * capacity);
                assertThat(rejectedSessionCount("capacity"))
                        .isEqualTo((double) (wave + 1) * (connectionsPerWave - capacity));

                runConcurrently(
                        executor,
                        sessions,
                        session -> decorated.afterConnectionClosed(session, CloseStatus.NORMAL)
                );

                assertThat(activeSessionCount()).isZero();
            }
        }

        WebSocketSession replacementSession = session("replacement-after-pressure");
        decorated.afterConnectionEstablished(replacementSession);

        assertThat(activeSessionCount()).isEqualTo(1D);
        assertThat(acceptedConnections).hasValue(waveCount * capacity + 1);
    }

    @Test
    void sustainedConnectionChurnDoesNotLeakSlotsOrDoubleCloseMetrics() throws Exception {
        int connectionCount = 10_000;
        properties.getRealtime().setMaxSessionsPerInstance(64);
        registry.registerMetrics();
        CountingWebSocketHandler handler = new CountingWebSocketHandler();
        WebSocketHandler decorated = registry.decorate(handler);

        for (int index = 0; index < connectionCount; index++) {
            WebSocketSession session = session("churn-session-" + index);
            decorated.afterConnectionEstablished(session);
            decorated.afterConnectionClosed(session, CloseStatus.NORMAL);
            decorated.afterConnectionClosed(session, CloseStatus.NORMAL);
            if ((index + 1) % 1000 == 0) {
                assertThat(activeSessionCount()).isZero();
            }
        }

        assertThat(activeSessionCount()).isZero();
        assertThat(handler.establishedConnections).hasValue(connectionCount);
        assertThat(handler.closedConnections).hasValue(connectionCount);
    }

    @Test
    void unauthenticatedFloodCannotExhaustInstanceCapacity() throws Exception {
        properties.getRealtime().setMaxSessionsPerInstance(8);
        properties.getRealtime().setMaxPendingSessionsPerInstance(2);
        registry.registerMetrics();
        WebSocketHandler handler = Mockito.mock(WebSocketHandler.class);
        WebSocketHandler decorated = registry.decorate(handler);
        WebSocketSession first = session("pending-1");
        WebSocketSession second = session("pending-2");
        WebSocketSession third = session("pending-3");

        decorated.afterConnectionEstablished(first);
        decorated.afterConnectionEstablished(second);
        decorated.afterConnectionEstablished(third);

        // 未认证连接只受待认证配额约束：超出即拒，且一格实例容量都不许被它们占住。
        assertThat(pendingSessionCount()).isEqualTo(2D);
        assertThat(activeSessionCount()).isEqualTo(2D);
        assertThat(rejectedSessionCount("pending")).isEqualTo(1D);
        Mockito.verify(handler, Mockito.never()).afterConnectionEstablished(third);
        Mockito.verify(third).close(Mockito.argThat(status -> status.getCode() == 1013));

        registry.authorize("pending-1", UUID.randomUUID(), UUID.randomUUID(), Instant.now().plusSeconds(600));
        // 晋升只归还自己那一格待认证配额，第二条连接仍占着剩下的那一格。
        assertThat(pendingSessionCount()).isEqualTo(1D);

        WebSocketSession fourth = session("pending-4");
        decorated.afterConnectionEstablished(fourth);
        Mockito.verify(handler).afterConnectionEstablished(fourth);
        assertThat(activeSessionCount()).isEqualTo(3D);
    }

    @Test
    void closingAuthorizedSessionDoesNotReturnPendingQuotaTwice() throws Exception {
        properties.getRealtime().setMaxSessionsPerInstance(4);
        properties.getRealtime().setMaxPendingSessionsPerInstance(1);
        registry.registerMetrics();
        WebSocketHandler handler = Mockito.mock(WebSocketHandler.class);
        WebSocketHandler decorated = registry.decorate(handler);
        WebSocketSession session = session("promoted-then-closed");

        decorated.afterConnectionEstablished(session);
        registry.authorize("promoted-then-closed", UUID.randomUUID(), UUID.randomUUID(),
                Instant.now().plusSeconds(600));
        decorated.afterConnectionClosed(session, CloseStatus.NORMAL);

        // 晋升时已归还待认证配额，关闭时不能再扣一次：负数会把这道限流变成摆设。
        assertThat(pendingSessionCount()).isZero();
        assertThat(activeSessionCount()).isZero();

        WebSocketSession next = session("next-after-close");
        decorated.afterConnectionEstablished(next);
        Mockito.verify(handler).afterConnectionEstablished(next);
    }

    private void runConcurrently(
            ExecutorService executor,
            List<WebSocketSession> sessions,
            SessionOperation operation
    ) throws Exception {
        CountDownLatch startGate = new CountDownLatch(1);
        List<Future<Void>> futures = sessions.stream()
                .map(session -> executor.submit(() -> {
                    startGate.await();
                    operation.execute(session);
                    return (Void) null;
                }))
                .toList();
        startGate.countDown();
        for (Future<Void> future : futures) {
            future.get();
        }
    }

    private double activeSessionCount() {
        return meterRegistry.get("omninest.sync.realtime.sessions.active").gauge().value();
    }

    private double pendingSessionCount() {
        return meterRegistry.get("omninest.sync.realtime.sessions.pending").gauge().value();
    }

    private double rejectedSessionCount(String reason) {
        return meterRegistry.get("omninest.sync.realtime.sessions.rejected")
                .tag("reason", reason)
                .counter()
                .count();
    }

    private WebSocketSession session(String id) {
        WebSocketSession session = Mockito.mock(WebSocketSession.class);
        Mockito.when(session.getId()).thenReturn(id);
        Mockito.when(session.isOpen()).thenReturn(true);
        return session;
    }

    @FunctionalInterface
    private interface SessionOperation {
        void execute(WebSocketSession session) throws Exception;
    }

    /**
     * 仅记录连接生命周期次数的测试处理器。
     *
     * @author OmniNest
     */
    private static final class CountingWebSocketHandler implements WebSocketHandler {
        private final AtomicInteger establishedConnections = new AtomicInteger();
        private final AtomicInteger closedConnections = new AtomicInteger();

        /**
         * 记录连接建立。
         *
         * @param session WebSocket 会话
         */
        @Override
        public void afterConnectionEstablished(WebSocketSession session) {
            establishedConnections.incrementAndGet();
        }

        /**
         * 忽略容量测试未使用的消息。
         *
         * @param session WebSocket 会话
         * @param message WebSocket 消息
         */
        @Override
        public void handleMessage(WebSocketSession session, WebSocketMessage<?> message) {
        }

        /**
         * 忽略容量测试未使用的传输异常。
         *
         * @param session WebSocket 会话
         * @param exception 传输异常
         */
        @Override
        public void handleTransportError(WebSocketSession session, Throwable exception) {
        }

        /**
         * 记录连接关闭。
         *
         * @param session WebSocket 会话
         * @param closeStatus 关闭状态
         */
        @Override
        public void afterConnectionClosed(WebSocketSession session, CloseStatus closeStatus) {
            closedConnections.incrementAndGet();
        }

        /**
         * 返回不支持分片消息。
         *
         * @return 固定返回 false
         */
        @Override
        public boolean supportsPartialMessages() {
            return false;
        }
    }
}
