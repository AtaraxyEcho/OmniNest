package com.omninest.modules.file.config;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import java.util.LinkedHashMap;
import java.util.Map;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;
import org.springframework.validation.annotation.Validated;

/**
 * 本地媒体只读挂载配置。
 *
 * @author OmniNest
 */
@Data
@Component
@Validated
@ConfigurationProperties(prefix = "file.local-media")
public class LocalMediaStorageProperties {

    private boolean enabled;

    private String nodeId = "local-node";

    @Min(1)
    @Max(1000000)
    private int maxFilesPerScan = 100000;

    @Min(1)
    @Max(128)
    private int maxScanDepth = 32;

    @Valid
    private Map<String, MountProperties> mounts = new LinkedHashMap<>();

    /**
     * 单个受信任挂载点配置。
     *
     * @author OmniNest
     */
    @Data
    @NoArgsConstructor
    @AllArgsConstructor
    public static class MountProperties {

        private String hostPath;

        private String processPath;
    }
}
