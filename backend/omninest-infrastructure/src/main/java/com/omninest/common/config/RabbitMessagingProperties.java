package com.omninest.common.config;

import java.time.Duration;
import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * RabbitMQ 客户端消息容量和积压监控配置。
 *
 * @author OmniNest
 */
@Data
@ConfigurationProperties(prefix = "omninest.messaging.rabbit")
public class RabbitMessagingProperties {

    private int maximumMessageBytes = 1024 * 1024;

    private Duration messageTtl = Duration.ofDays(7);

    private int consumerPrefetch = 10;

    private boolean backlogMonitoringEnabled = true;

    private long backlogWarningMessages = 10_000L;

    private long backlogCriticalMessages = 50_000L;
}
