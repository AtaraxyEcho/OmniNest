package com.omninest.worker.storage;

import java.time.Duration;
import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 原件存储桶孤儿对象扫描配置。
 *
 * <p>{@code deleteEnabled} 默认关闭：原件不可重建，误删即永久丢失用户数据，
 * 因此首轮只出报表。{@code minimumAge} 默认 30 天，必须大于过期会话回收窗口
 * （7 天）与隔离对象保留期（默认 7 天）之和再加余量。</p>
 *
 * @author OmniNest
 */
@Data
@ConfigurationProperties(prefix = "omninest.storage.user-file-orphan-scan")
public class UserFileOrphanScanProperties {

    private boolean enabled = true;

    private boolean deleteEnabled;

    private String prefix = "";

    private Duration minimumAge = Duration.ofDays(30);

    private int pageSize = 500;

    private int maximumPagesPerRun = 20;

    private int maximumDeletesPerRun = 100;

    private Duration cursorTtl = Duration.ofDays(30);

    private Duration lockTtl = Duration.ofMinutes(30);
}
