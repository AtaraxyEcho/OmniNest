package com.omninest.modules.sync.realtime;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.security.SessionRevocationChecker;
import com.omninest.common.security.TokenAuthorityMapper;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.MessageBuilder;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

/**
 * STOMP 实时认证拦截器单元测试。
 *
 * @author OmniNest
 */
class RealtimeStompAuthenticationInterceptorTest {

    private final JwtDecoder jwtDecoder = Mockito.mock(JwtDecoder.class);
    private final SessionRevocationChecker revocationChecker = Mockito.mock(SessionRevocationChecker.class);
    private final RealtimeWebSocketSessionRegistry sessionRegistry =
            Mockito.mock(RealtimeWebSocketSessionRegistry.class);
    private final RealtimeStompAuthenticationInterceptor interceptor =
            new RealtimeStompAuthenticationInterceptor(
                    jwtDecoder,
                    revocationChecker,
                    sessionRegistry
            );

    @Test
    void connectAuthenticatesAccessTokenAndAssociatesSession() {
        UUID userId = UUID.randomUUID();
        UUID sid = UUID.randomUUID();
        Instant expiresAt = Instant.now().plusSeconds(600);
        Jwt jwt = jwt(userId, sid, expiresAt);
        Mockito.when(jwtDecoder.decode("valid-token")).thenReturn(jwt);
        Mockito.when(revocationChecker.isRevoked(userId, sid)).thenReturn(false);
        StompHeaderAccessor accessor = accessor(StompCommand.CONNECT);
        accessor.setSessionId("ws-session-1");
        accessor.setNativeHeader("Authorization", "Bearer valid-token");

        interceptor.preSend(message(accessor), Mockito.mock(MessageChannel.class));

        assertThat(accessor.getUser()).isNotNull();
        assertThat(accessor.getUser().getName()).isEqualTo(userId.toString());
        Mockito.verify(sessionRegistry).authorize("ws-session-1", userId, sid, expiresAt);
    }

    @Test
    void connectRejectsRevokedSession() {
        UUID userId = UUID.randomUUID();
        UUID sid = UUID.randomUUID();
        Jwt jwt = jwt(userId, sid, Instant.now().plusSeconds(600));
        Mockito.when(jwtDecoder.decode("revoked-token")).thenReturn(jwt);
        Mockito.when(revocationChecker.isRevoked(userId, sid)).thenReturn(true);
        StompHeaderAccessor accessor = accessor(StompCommand.CONNECT);
        accessor.setSessionId("ws-session-2");
        accessor.setNativeHeader("authorization", "Bearer revoked-token");

        assertThatThrownBy(() -> interceptor.preSend(
                message(accessor),
                Mockito.mock(MessageChannel.class)
        )).isInstanceOf(RealtimeAuthenticationException.class)
                .hasMessageContaining("已撤销");
    }

    @Test
    void connectRejectsMissingBearerHeader() {
        StompHeaderAccessor accessor = accessor(StompCommand.CONNECT);
        accessor.setSessionId("ws-session-3");

        assertThatThrownBy(() -> interceptor.preSend(
                message(accessor),
                Mockito.mock(MessageChannel.class)
        )).isInstanceOf(RealtimeAuthenticationException.class)
                .hasMessageContaining("缺少 Bearer");
    }

    @Test
    void subscribeAllowsOnlyUserRealtimeDestinations() {
        StompHeaderAccessor allowed = authenticatedAccessor(StompCommand.SUBSCRIBE);
        allowed.setDestination("/user/queue/sync");
        StompHeaderAccessor denied = authenticatedAccessor(StompCommand.SUBSCRIBE);
        denied.setDestination("/topic/all-users");

        Message<?> result = interceptor.preSend(
                message(allowed),
                Mockito.mock(MessageChannel.class)
        );

        assertThat(result).isNotNull();
        assertThatThrownBy(() -> interceptor.preSend(
                message(denied),
                Mockito.mock(MessageChannel.class)
        )).isInstanceOf(RealtimeAuthenticationException.class)
                .hasMessageContaining("不允许订阅");
    }

    @Test
    void sendCommandIsAlwaysRejected() {
        StompHeaderAccessor accessor = authenticatedAccessor(StompCommand.SEND);
        accessor.setDestination("/app/anything");

        assertThatThrownBy(() -> interceptor.preSend(
                message(accessor),
                Mockito.mock(MessageChannel.class)
        )).isInstanceOf(RealtimeAuthenticationException.class)
                .hasMessageContaining("不允许使用");
    }

    private StompHeaderAccessor accessor(StompCommand command) {
        StompHeaderAccessor accessor = StompHeaderAccessor.create(command);
        accessor.setLeaveMutable(true);
        return accessor;
    }

    private StompHeaderAccessor authenticatedAccessor(StompCommand command) {
        UUID userId = UUID.randomUUID();
        UUID sid = UUID.randomUUID();
        Mockito.when(revocationChecker.isRevoked(userId, sid)).thenReturn(false);
        Jwt jwt = jwt(userId, sid, Instant.now().plusSeconds(600));
        StompHeaderAccessor accessor = accessor(command);
        accessor.setUser(new JwtAuthenticationToken(
                jwt,
                List.of(new SimpleGrantedAuthority(TokenAuthorityMapper.ACCESS_TOKEN_AUTHORITY)),
                userId.toString()
        ));
        return accessor;
    }

    @Test
    void subscribeRejectsSessionRevokedAfterConnect() {
        StompHeaderAccessor accessor = authenticatedAccessor(StompCommand.SUBSCRIBE);
        accessor.setDestination("/user/queue/sync");
        UUID userId = UUID.fromString(accessor.getUser().getName());
        UUID sid = UUID.fromString(
                ((JwtAuthenticationToken) accessor.getUser()).getToken().getClaimAsString("sid"));
        Mockito.when(revocationChecker.isRevoked(userId, sid)).thenReturn(true);

        assertThatThrownBy(() -> interceptor.preSend(
                message(accessor),
                Mockito.mock(MessageChannel.class)
        )).isInstanceOf(RealtimeAuthenticationException.class)
                .hasMessageContaining("已撤销");
    }

    private Message<byte[]> message(StompHeaderAccessor accessor) {
        return MessageBuilder.createMessage(new byte[0], accessor.getMessageHeaders());
    }

    private Jwt jwt(UUID userId, UUID sid, Instant expiresAt) {
        return Jwt.withTokenValue("token")
                .header("alg", "HS256")
                .subject(userId.toString())
                .claim("sid", sid.toString())
                .claim("token_use", "access")
                .issuedAt(Instant.now())
                .expiresAt(expiresAt)
                .build();
    }
}
