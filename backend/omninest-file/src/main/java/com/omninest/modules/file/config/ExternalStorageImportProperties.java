package com.omninest.modules.file.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 外部存储导入护栏配置。
 *
 * @author OmniNest
 */
@Data
@ConfigurationProperties(prefix = "omninest.external-storage.import")
public class ExternalStorageImportProperties {

    /**
     * 单文件体积上限（字节）。0 表示不限制。默认 15GB，用于拦截 4K 原盘误导入。
     */
    private long maxFileBytes = 15L * 1024 * 1024 * 1024;

    /**
     * 单次导入任务预估总量上限（字节）。0 表示不限制。
     */
    private long maxTotalBytes = 0L;
}
