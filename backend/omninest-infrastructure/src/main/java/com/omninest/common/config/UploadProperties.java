package com.omninest.common.config;

import com.omninest.common.upload.FileUploadSettings;
import java.time.Duration;
import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 上传相关配置属性。
 *
 * @author OmniNest
 */
@Data
@ConfigurationProperties(prefix = "omninest.upload")
public class UploadProperties implements FileUploadSettings {
    /** 预签名 URL 有效期 */
    private Duration urlTtl = Duration.ofHours(4);

    /** 上传会话有效期 */
    private Duration sessionTtl = Duration.ofHours(24);

    /** 带宽限速配置 */
    private Bandwidth bandwidth = new Bandwidth();

    @Override
    public Duration presignedUrlTtl() {
        return urlTtl;
    }

    @Override
    public Duration sessionTtl() {
        return sessionTtl;
    }

    @Override
    public boolean bandwidthLimitEnabled() {
        return bandwidth.isEnabled();
    }

    @Override
    public int maxPresignedPartsPerSecond() {
        return bandwidth.getMaxPartsPerSecond();
    }

    @Override
    public int presignedPartBurstCapacity() {
        return bandwidth.getBurstCapacity();
    }

    /**
     * 上传预签名地址签发限速配置。
     *
     * @author OmniNest
     */
    @Data
    public static class Bandwidth {
        /** 每用户每秒签发 presigned URL 上限 */
        private int maxPartsPerSecond = 4;

        /** 令牌桶突发容量 */
        private int burstCapacity = 8;

        /** 是否启用带宽限速 */
        private boolean enabled = true;
    }
}
