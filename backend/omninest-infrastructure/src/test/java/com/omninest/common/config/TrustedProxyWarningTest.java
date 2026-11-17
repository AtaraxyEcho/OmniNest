package com.omninest.common.config;

import java.util.List;
import org.junit.jupiter.api.Test;

/**
 * 可信代理启动告警的边界：清单为空或未注入时只告警，不得影响启动。
 *
 * @author OmniNest
 */
class TrustedProxyWarningTest {

    @Test
    void doesNotFailWhenTrustedProxiesAreUnset() {
        SecurityProperties properties = new SecurityProperties();
        properties.setTrustedProxies(null);

        new TrustedProxyWarning(properties).warnIfUnset();
    }

    @Test
    void doesNotFailWhenTrustedProxiesAreBlank() {
        SecurityProperties properties = new SecurityProperties();
        properties.setTrustedProxies(List.of("", "  "));

        new TrustedProxyWarning(properties).warnIfUnset();
    }

    @Test
    void doesNotFailWhenTrustedProxiesAreConfigured() {
        SecurityProperties properties = new SecurityProperties();
        properties.setTrustedProxies(List.of("172.30.0.10"));

        new TrustedProxyWarning(properties).warnIfUnset();
    }
}
