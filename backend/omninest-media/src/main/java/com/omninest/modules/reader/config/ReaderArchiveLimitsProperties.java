package com.omninest.modules.reader.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * Reader 压缩包输入与解压容量限制。
 *
 * @author OmniNest
 */
@Data
@Component
@ConfigurationProperties(prefix = "reader.archive-limits")
public class ReaderArchiveLimitsProperties {

    private long maxArchiveBytes = 2L * 1024 * 1024 * 1024;
    private int maxEntries = 20_000;
    private long maxEntryBytes = 64L * 1024 * 1024;
    private long maxTotalUncompressedBytes = 4L * 1024 * 1024 * 1024;
    private double maxCompressionRatio = 200.0;
    private long compressionRatioCheckThresholdBytes = 1024L * 1024;
}
