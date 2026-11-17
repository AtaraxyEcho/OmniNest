package com.omninest.modules.file.config;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;
import org.springframework.validation.annotation.Validated;

/**
 * 上传会话与分片大小限制。
 *
 * <p>这些阈值原先写死在服务类里：客户端只能从 {@code FILE_SIZE_EXCEEDED} 失败反推上限，
 * 运维也无法按部署调大。集中到配置后，策略接口同时下发有效上限。</p>
 *
 * @author OmniNest
 */
@Data
@Component
@Validated
@ConfigurationProperties(prefix = "file.upload-limits")
public class FileUploadLimitsProperties {

    /** 单用户未完成上传会话的并发上限。 */
    @Min(1)
    @Max(1000)
    private int maxActiveUploadSessions = 20;

    /** 直传（单请求 PUT）允许的最大字节数；超过后必须走分片。 */
    @Min(1)
    private long directUploadMaxBytes = 64L * 1024 * 1024;

    /** 单次上传可并发签发的分片数。 */
    @Min(1)
    @Max(64)
    private int maxConcurrentParts = 4;

    /** 分片下限：低于该值会让分片数暴涨。 */
    @Min(1)
    private int minPartSizeBytes = 10 * 1024 * 1024;

    /** 默认分片大小。 */
    @Min(1)
    private int defaultPartSizeBytes = 10 * 1024 * 1024;

    /** 单个分片上限。 */
    @Min(1)
    private int maxPartSizeBytes = 100 * 1024 * 1024;

    /** 单次上传的分片总数上限，与分片大小共同决定单文件上限。 */
    @Min(1)
    @Max(10000)
    private int maxTotalParts = 1000;

    /** 规划分片数时的目标值：按文件大小反推接近该数量的分片大小。 */
    @Min(1)
    private int targetParts = 64;

    /**
     * 单文件有效上限：分片大小上限与分片数上限的乘积。
     *
     * @return 单文件最大字节数
     */
    public long maxFileSizeBytes() {
        return (long) maxPartSizeBytes * maxTotalParts;
    }
}
