package com.omninest.common.security;

import com.omninest.common.config.ClamAvRuntimeConfig;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.health.contributor.Health;
import org.springframework.boot.health.contributor.HealthIndicator;
import org.springframework.stereotype.Component;

/**
 * ClamAV 服务健康探针。
 *
 * @author OmniNest
 */
@Component
@RequiredArgsConstructor
public class ClamAvHealthIndicator implements HealthIndicator {
    private static final int HEALTH_TIMEOUT_MILLIS = 3000;

    private final ClamAvScanner scanner;
    private final ClamAvRuntimeConfig runtimeConfig;

    /**
     * 检查 ClamAV 配置和 clamd 连接状态。
     *
     * @return 健康状态
     */
    @Override
    public Health health() {
        if (!runtimeConfig.isEnabled()) {
            return Health.unknown()
                    .withDetail("enabled", false)
                    .withDetail("message", "ClamAV 扫描已关闭")
                    .build();
        }
        String host = runtimeConfig.host();
        int port = runtimeConfig.port();
        if (scanner.ping(host, port, HEALTH_TIMEOUT_MILLIS)) {
            return Health.up()
                    .withDetail("enabled", true)
                    .withDetail("host", host)
                    .withDetail("port", port)
                    .build();
        }
        return Health.down()
                .withDetail("enabled", true)
                .withDetail("host", host)
                .withDetail("port", port)
                .withDetail("message", "clamd 无法连接")
                .build();
    }
}
