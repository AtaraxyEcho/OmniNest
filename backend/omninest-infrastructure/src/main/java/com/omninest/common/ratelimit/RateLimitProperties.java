package com.omninest.common.ratelimit;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "omninest.rate-limit")
public record RateLimitProperties(
        boolean enabled,
        int defaultLimit,
        Duration defaultWindow,
        String keyPrefix
) {
    public RateLimitProperties {
        if (defaultLimit <= 0) {
            defaultLimit = 120;
        }
        if (defaultWindow == null) {
            defaultWindow = Duration.ofMinutes(1);
        }
        if (keyPrefix == null || keyPrefix.isBlank()) {
            keyPrefix = "omninest:rate-limit";
        }
    }
}
