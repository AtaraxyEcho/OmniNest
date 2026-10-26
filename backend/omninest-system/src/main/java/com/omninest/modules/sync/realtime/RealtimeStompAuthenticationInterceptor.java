package com.omninest.modules.sync.realtime;

import com.omninest.common.security.SessionRevocationChecker;
import com.omninest.common.security.TokenAuthorityMapper;
import java.time.Instant;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.messaging.support.MessageHeaderAccessor;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Component;

/**
 * 对 STOMP CONNECT 进行 JWT 认证并限制客户端可用命令和订阅目标。
 *
 * @author OmniNest
 */
@Component
@RequiredArgsConstructor
@ConditionalOnProperty(
        prefix = "omninest.runtime",
        name = "role",
        havingValue = "api",
        matchIfMissing = true
)
public class RealtimeStompAuthenticationInterceptor implements ChannelInterceptor {

    private static final String SYNC_DESTINATION = "/user/queue/sync";
    private static final String NOTIFICATION_DESTINATION = "/user/queue/notifications";

    private final JwtDecoder jwtDecoder;
    private final SessionRevocationChecker sessionRevocationChecker;
    private final RealtimeWebSocketSessionRegistry sessionRegistry;

    /**
     * 认证和授权客户端入站 STOMP 帧。
     *
     * @param message STOMP 消息
     * @param channel 入站消息通道
     * @return 允许继续处理的消息
     */
    @Override
    public Message<?> preSend(Message<?> message, MessageChannel channel) {
        StompHeaderAccessor accessor = MessageHeaderAccessor.getAccessor(
                message,
                StompHeaderAccessor.class
        );
        if (accessor == null || accessor.getCommand() == null) {
            return message;
        }
        StompCommand command = accessor.getCommand();
        switch (command) {
            case CONNECT, STOMP -> authenticate(accessor);
            case SUBSCRIBE -> authorizeSubscription(accessor);
            case UNSUBSCRIBE, DISCONNECT -> requireAuthentication(accessor);
            default -> throw new RealtimeAuthenticationException("不允许使用该 STOMP 命令");
        }
        return message;
    }

    private void authenticate(StompHeaderAccessor accessor) {
        String token = bearerToken(accessor);
        Jwt jwt;
        try {
            jwt = jwtDecoder.decode(token);
        } catch (JwtException | IllegalArgumentException ex) {
            throw new RealtimeAuthenticationException("实时连接凭证无效", ex);
        }

        UUID userId = parseUuid(jwt.getSubject(), "JWT sub 无效");
        UUID sid = parseUuid(jwt.getClaimAsString("sid"), "JWT sid 无效");
        Instant expiresAt = jwt.getExpiresAt();
        if (expiresAt == null || !expiresAt.isAfter(Instant.now())) {
            throw new RealtimeAuthenticationException("实时连接凭证已过期");
        }
        if (sessionRevocationChecker.isRevoked(userId, sid)) {
            throw new RealtimeAuthenticationException("实时连接会话已撤销");
        }

        Collection<String> authorityNames = TokenAuthorityMapper.map(jwt.getClaims());
        List<GrantedAuthority> safeAuthorities = authorityNames.stream()
                .map(authority -> (GrantedAuthority) new SimpleGrantedAuthority(authority))
                .toList();
        boolean accessToken = safeAuthorities.stream()
                .anyMatch(authority -> TokenAuthorityMapper.ACCESS_TOKEN_AUTHORITY.equals(authority.getAuthority()));
        if (!accessToken) {
            throw new RealtimeAuthenticationException("实时连接必须使用访问令牌");
        }

        String sessionId = accessor.getSessionId();
        if (sessionId == null || sessionId.isBlank()) {
            throw new RealtimeAuthenticationException("WebSocket 会话标识缺失");
        }
        JwtAuthenticationToken authentication = new JwtAuthenticationToken(
                jwt,
                safeAuthorities,
                userId.toString()
        );
        accessor.setUser(authentication);
        sessionRegistry.authorize(sessionId, userId, sid, expiresAt);
    }

    private void authorizeSubscription(StompHeaderAccessor accessor) {
        requireAuthentication(accessor);
        String destination = accessor.getDestination();
        if (!SYNC_DESTINATION.equals(destination) && !NOTIFICATION_DESTINATION.equals(destination)) {
            throw new RealtimeAuthenticationException("不允许订阅该实时目标");
        }
    }

    private void requireAuthentication(StompHeaderAccessor accessor) {
        if (!(accessor.getUser() instanceof JwtAuthenticationToken authentication)
                || !authentication.isAuthenticated()
                || authentication.getAuthorities().stream().noneMatch(authority ->
                        TokenAuthorityMapper.ACCESS_TOKEN_AUTHORITY.equals(authority.getAuthority()))) {
            throw new RealtimeAuthenticationException("实时连接尚未认证");
        }
        // 长连接不能让 CONNECT 成为唯一一次校验：令牌过期或会话被强制下线后，
        // 后续帧必须立即失效。
        Jwt jwt = authentication.getToken();
        Instant expiresAt = jwt.getExpiresAt();
        if (expiresAt == null || !expiresAt.isAfter(Instant.now())) {
            throw new RealtimeAuthenticationException("实时连接凭证已过期");
        }
        UUID userId = parseUuid(jwt.getSubject(), "JWT sub 无效");
        UUID sid = parseUuid(jwt.getClaimAsString("sid"), "JWT sid 无效");
        if (sessionRevocationChecker.isRevoked(userId, sid)) {
            throw new RealtimeAuthenticationException("实时连接会话已撤销");
        }
    }

    private String bearerToken(StompHeaderAccessor accessor) {
        String authorization = accessor.getFirstNativeHeader("Authorization");
        if (authorization == null || authorization.isBlank()) {
            authorization = accessor.getFirstNativeHeader("authorization");
        }
        if (authorization == null
                || authorization.length() <= 7
                || !authorization.regionMatches(true, 0, "Bearer ", 0, 7)) {
            throw new RealtimeAuthenticationException("实时连接缺少 Bearer 凭证");
        }
        return authorization.substring(7).trim();
    }

    private UUID parseUuid(String value, String message) {
        try {
            return UUID.fromString(value);
        } catch (RuntimeException ex) {
            throw new RealtimeAuthenticationException(message, ex);
        }
    }
}
