package com.omninest.modules.photos.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * 照片输入和解码容量限制。
 *
 * @author OmniNest
 */
@Data
@Component
@ConfigurationProperties(prefix = "photo.media-limits")
public class PhotoMediaLimitsProperties {

    private long maxStandardFileBytes = 128L * 1024 * 1024;
    private long maxRawFileBytes = 512L * 1024 * 1024;
    private int maxWidth = 30_000;
    private int maxHeight = 30_000;
    private long maxPixels = 100_000_000L;
    private long maxDecodedBytes = 400L * 1024 * 1024;
}
