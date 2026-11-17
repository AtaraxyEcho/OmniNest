package com.omninest.worker.storage;

import java.time.Duration;
import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 派生对象孤儿扫描配置。
 *
 * @author OmniNest
 */
@Data
@ConfigurationProperties(prefix = "omninest.storage.derived-orphan-scan")
public class DerivedAssetOrphanScanProperties {

    private boolean enabled = true;

    private boolean deleteEnabled;

    private String prefix = "";

    private Duration minimumAge = Duration.ofHours(24);

    private int pageSize = 500;

    private int maximumPagesPerRun = 20;

    private int maximumDeletesPerRun = 100;

    private Duration cursorTtl = Duration.ofDays(30);

    private Duration lockTtl = Duration.ofMinutes(30);
}
