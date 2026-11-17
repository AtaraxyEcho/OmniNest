package com.omninest.modules.task.config;

import java.util.UUID;
import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 任务 Outbox 发布参数。
 *
 * @author OmniNest
 */
@Data
@ConfigurationProperties(prefix = "omninest.task.outbox")
public class TaskOutboxProperties {
    private boolean enabled = true;
    private long intervalMillis = 500L;
    private int batchSize = 100;
    private long leaseSeconds = 30L;
    private long confirmTimeoutMillis = 5000L;
    private String instanceId = UUID.randomUUID().toString();
}
