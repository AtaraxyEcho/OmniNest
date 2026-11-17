package com.omninest.common.security;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.common.config.SecurityProperties;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class TrustedProxyClientIpResolverTest {
    private TrustedProxyClientIpResolver resolver;

    @BeforeEach
    void setUp() {
        SecurityProperties properties = new SecurityProperties();
        properties.setTrustedProxies(List.of("10.0.0.0/8", "127.0.0.1/32", "2001:db8::/32"));
        resolver = new TrustedProxyClientIpResolver(properties);
    }

    @Test
    void ignoresForwardedHeadersFromUntrustedPeer() {
        String resolved = resolver.resolve("198.51.100.20", "203.0.113.8", "203.0.113.9");

        assertThat(resolved).isEqualTo("198.51.100.20");
    }

    @Test
    void resolvesFirstUntrustedAddressFromRightOfTrustedChain() {
        String resolved = resolver.resolve(
                "10.0.0.3",
                "203.0.113.8, 10.0.0.1, 10.0.0.2",
                null
        );

        assertThat(resolved).isEqualTo("203.0.113.8");
    }

    @Test
    void rejectsEntireMalformedForwardedChain() {
        String resolved = resolver.resolve("10.0.0.3", "203.0.113.8, invalid", "203.0.113.9");

        assertThat(resolved).isEqualTo("10.0.0.3");
    }

    @Test
    void usesRealIpOnlyWhenDirectPeerIsTrustedAndForwardedForIsAbsent() {
        String resolved = resolver.resolve("127.0.0.1", null, "203.0.113.9");

        assertThat(resolved).isEqualTo("203.0.113.9");
    }

    @Test
    void returnsDirectPeerWhenNoTrustedProxyIsConfigured() {
        TrustedProxyClientIpResolver strictResolver =
                new TrustedProxyClientIpResolver(new SecurityProperties());

        String resolved = strictResolver.resolve("127.0.0.1", "203.0.113.8", "203.0.113.9");

        assertThat(resolved).isEqualTo("127.0.0.1");
    }
}
