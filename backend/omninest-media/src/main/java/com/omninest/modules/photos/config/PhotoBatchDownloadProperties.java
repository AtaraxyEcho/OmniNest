package com.omninest.modules.photos.config;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;
import org.springframework.validation.annotation.Validated;

/**
 * 照片批量下载的文件数量、源文件容量和临时磁盘限制。
 *
 * @author OmniNest
 */
@Data
@Component
@Validated
@ConfigurationProperties(prefix = "photo.batch-download")
public class PhotoBatchDownloadProperties {

    @Min(1)
    @Max(1000)
    private int maxFiles = 1000;

    @Min(1)
    private long maxSingleFileBytes = 512L * 1024 * 1024;

    @Min(1)
    private long maxSourceBytes = 20L * 1024 * 1024 * 1024;

    @Min(0)
    private long minFreeBytes = 512L * 1024 * 1024;
}
