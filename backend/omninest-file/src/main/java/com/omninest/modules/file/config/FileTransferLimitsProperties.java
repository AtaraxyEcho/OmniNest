package com.omninest.modules.file.config;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;
import org.springframework.validation.annotation.Validated;

/**
 * 文件传输与派生资产存储的资源限制。
 *
 * @author OmniNest
 */
@Data
@Component
@Validated
@ConfigurationProperties(prefix = "file.transfer-limits")
public class FileTransferLimitsProperties {

    @Min(1)
    @Max(100000)
    private int maxFilesPerTask = 10000;

    /**
     * 单个派生资产对象的字节上限，用于拦截异常产物写满磁盘。
     * 转码、下载包等登记在 LARGE_ASSET_TYPES 的完整内容产物不受该上限约束。
     */
    @Min(1)
    private long maxDerivedAssetBytes = 512L * 1024 * 1024;
}
