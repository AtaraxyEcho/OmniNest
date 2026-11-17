package com.omninest.modules.video.config;

import java.time.Duration;
import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * Web 端实时转码流的并发配置。
 *
 * @author OmniNest
 */
@Getter
@Setter
@Component
@ConfigurationProperties(prefix = "video.stream")
public class VideoStreamProperties {

    /** 同一时刻允许的实时 ffmpeg 流数量。 */
    private int maxConcurrentStreams = 4;

    /** 等待空闲槽位的最长时间：给客户端断开后旧进程释放槽位留出余量。 */
    private Duration slotWaitTimeout = Duration.ofSeconds(2);
}
