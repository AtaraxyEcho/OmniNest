package com.omninest.modules.sync.config;

import java.util.UUID;
import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 同步事件发布与保留策略配置。
 *
 * @author OmniNest
 */
@Data
@ConfigurationProperties(prefix = "omninest.sync")
public class SyncEventProperties {

    private Outbox outbox = new Outbox();
    private Retention retention = new Retention();
    private Realtime realtime = new Realtime();

    /**
     * Outbox 发布配置。
     *
     * @author OmniNest
     */
    @Data
    public static class Outbox {
        private boolean enabled = true;
        private long intervalMillis = 500L;
        private int batchSize = 100;
        private long leaseSeconds = 30L;
        private long confirmTimeoutMillis = 5000L;
        private String instanceId = UUID.randomUUID().toString();
    }

    /**
     * 已发布事件保留配置。
     *
     * @author OmniNest
     */
    @Data
    public static class Retention {
        private boolean enabled = true;
        private int days = 30;
        private String cleanupCron = "0 15 2 * * *";
    }

    /**
     * WebSocket 实时会话配置。
     *
     * @author OmniNest
     */
    @Data
    public static class Realtime {
        private long sessionAuditMillis = 10_000L;
        private long authenticationTimeoutMillis = 15_000L;
        private int maxSessionsPerInstance = 500;
        private int maxPendingSessionsPerInstance = 64;
    }
}
