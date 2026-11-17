package com.omninest.worker.runtime;

import java.time.Duration;
import java.util.UUID;
import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Worker 心跳和外部依赖探测配置。
 *
 * @author OmniNest
 */
@Data
@ConfigurationProperties(prefix = "omninest.worker.runtime")
public class WorkerRuntimeProperties {

    private String instanceId = UUID.randomUUID().toString();
    private Duration heartbeatTtl = Duration.ofSeconds(45);
    private Duration probeTimeout = Duration.ofSeconds(3);
}
