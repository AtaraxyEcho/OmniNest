package com.omninest.common.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * AI 侧车服务配置属性。
 *
 * @author OmniNest
 */
@Data
@Component
@ConfigurationProperties(prefix = "photo.ai")
public class AiSidecarProperties {

    private String endpoint = "http://localhost:8090";
    private String secret;
    private int timeoutSeconds = 30;
    private long maxImageBytes = 64L * 1024 * 1024;
    private int maxResponseBytes = 1024 * 1024;
}
