package com.omninest.modules.photos.config;

import java.time.Duration;
import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * 照片批量任务终态记录的保留参数。
 *
 * @author OmniNest
 */
@Data
@Component
@ConfigurationProperties(prefix = "photo.batch-retention")
public class PhotoBatchRetentionProperties {

    /** 是否启用终态批量任务与打包 ZIP 的过期清理。 */
    private boolean enabled = true;

    /** 终态任务保留时长，超期后删除结果文件与任务行。 */
    private Duration maxAge = Duration.ofDays(7);

    /** 单轮清理的最大任务数。 */
    private int batchSize = 200;
}
