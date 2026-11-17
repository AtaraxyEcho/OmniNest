package com.omninest.modules.sync.config;

import com.omninest.common.security.BrowserSecurityPolicy;
import com.omninest.modules.sync.realtime.RealtimeStompAuthenticationInterceptor;
import com.omninest.modules.sync.realtime.RealtimeWebSocketSessionRegistry;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.simp.config.ChannelRegistration;
import org.springframework.messaging.simp.config.MessageBrokerRegistry;
import org.springframework.web.socket.config.annotation.EnableWebSocketMessageBroker;
import org.springframework.web.socket.config.annotation.StompEndpointRegistry;
import org.springframework.web.socket.config.annotation.WebSocketMessageBrokerConfigurer;
import org.springframework.web.socket.config.annotation.WebSocketTransportRegistration;

/**
 * 用户同步和通知共用的安全 WebSocket/STOMP 配置。
 *
 * @author OmniNest
 */
@Configuration
@EnableWebSocketMessageBroker
@RequiredArgsConstructor
@ConditionalOnProperty(
        prefix = "omninest.runtime",
        name = "role",
        havingValue = "api",
        matchIfMissing = true
)
public class RealtimeWebSocketConfig implements WebSocketMessageBrokerConfigurer {

    private final BrowserSecurityPolicy browserSecurityPolicy;
    private final RealtimeStompAuthenticationInterceptor authenticationInterceptor;
    private final RealtimeWebSocketSessionRegistry sessionRegistry;

    @Override
    public void configureMessageBroker(MessageBrokerRegistry config) {
        config.enableSimpleBroker("/topic", "/queue");
        config.setApplicationDestinationPrefixes("/app");
        config.setUserDestinationPrefix("/user");
    }

    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        registry.addEndpoint("/ws/realtime")
                .setAllowedOrigins(browserSecurityPolicy.allowedOrigins().toArray(new String[0]));
        registry.addEndpoint("/ws/notifications")
                .setAllowedOrigins(browserSecurityPolicy.allowedOrigins().toArray(new String[0]))
                .withSockJS();
    }

    @Override
    public void configureClientInboundChannel(ChannelRegistration registration) {
        registration.interceptors(authenticationInterceptor);
    }

    @Override
    public void configureWebSocketTransport(WebSocketTransportRegistration registration) {
        registration.addDecoratorFactory(sessionRegistry);
        registration.setTimeToFirstMessage(15_000);
        registration.setMessageSizeLimit(128 * 1024);
        registration.setSendBufferSizeLimit(512 * 1024);
        registration.setSendTimeLimit(10_000);
    }
}
