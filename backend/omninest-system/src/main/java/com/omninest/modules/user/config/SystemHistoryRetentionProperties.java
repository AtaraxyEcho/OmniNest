package com.omninest.modules.user.config;

import java.time.Duration;
import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 系统任务与审计日志保留策略配置。
 *
 * @author OmniNest
 */
@Data
@ConfigurationProperties(prefix = "omninest.history-retention")
public class SystemHistoryRetentionProperties {

    private boolean enabled = true;

    private Duration taskMaximumAge = Duration.ofDays(30);

    private Duration auditMaximumAge = Duration.ofDays(365);

    private Duration configMaximumAge = Duration.ofDays(365);

    /**
     * Outbox 投递记录保留时长。默认与任务记录一致：更短会让只剩事件子载荷的
     * 任务类型失去原样重放能力。
     */
    private Duration dispatchMaximumAge = Duration.ofDays(30);

    /**
     * 文件物理删除条目保留时长（仅清理成功终态）。
     */
    private Duration purgeEntryMaximumAge = Duration.ofDays(30);

    private int configMinimumVersions = 20;

    private int batchSize = 500;

    private int maximumBatches = 20;
}
