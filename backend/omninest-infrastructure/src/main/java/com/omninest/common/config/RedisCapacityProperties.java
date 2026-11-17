package com.omninest.common.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Redis 容量监控和分级告警配置。
 *
 * @author OmniNest
 */
@Data
@ConfigurationProperties(prefix = "omninest.redis.capacity")
public class RedisCapacityProperties {

    private boolean monitoringEnabled = true;

    private double memoryWarningRatio = 0.80D;

    private double memoryCriticalRatio = 0.90D;
}
