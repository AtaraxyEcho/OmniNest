package com.omninest.worker.runtime;

import com.omninest.common.runtime.WorkerRuntimeRegistry;
import com.omninest.common.runtime.WorkerRuntimeState;
import com.omninest.common.runtime.WorkerRuntimeState.CapabilityStatus;
import com.omninest.modules.photos.service.PhotosRuntimeConfigService;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 定时探测 Worker 外部依赖并发布短期运行状态。
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class WorkerRuntimeReporter {

    private final WorkerRuntimeRegistry runtimeRegistry;
    private final WorkerRuntimeProperties runtimeProperties;
    private final PhotosRuntimeConfigService photosRuntimeConfigService;
    private final HttpClient httpClient = HttpClient.newBuilder()
            .version(HttpClient.Version.HTTP_1_1)
            .followRedirects(HttpClient.Redirect.NEVER)
            .build();

    /**
     * 探测依赖并发布当前 Worker 状态。
     */
    @Scheduled(
            fixedDelayString = "${omninest.worker.runtime.heartbeat-interval:PT15S}",
            initialDelayString = "${omninest.worker.runtime.heartbeat-interval:PT15S}"
    )
    public void publish() {
        String instanceId = requireInstanceId();
        Map<String, CapabilityStatus> capabilities = new LinkedHashMap<>();
        capabilities.put(
                WorkerRuntimeState.PHOTO_AI_CAPABILITY,
                probePhotoAi()
        );
        runtimeRegistry.publish(
                new WorkerRuntimeState(instanceId, Instant.now(), capabilities),
                runtimeProperties.getHeartbeatTtl()
        );
        log.debug("已执行 Worker 运行状态上报: instanceId={}, capabilities={}", instanceId, capabilities);
    }

    private String requireInstanceId() {
        String instanceId = runtimeProperties.getInstanceId();
        if (instanceId == null || instanceId.isBlank()) {
            throw new IllegalStateException("Worker 实例标识不能为空");
        }
        return instanceId.trim();
    }

    private CapabilityStatus probePhotoAi() {
        if (!photosRuntimeConfigService.isAiEnabled()) {
            return CapabilityStatus.disabled("照片 AI 已在运行时配置中关闭");
        }
        try {
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(readinessUri(photosRuntimeConfigService.aiEndpoint()))
                    .timeout(runtimeProperties.getProbeTimeout())
                    .GET()
                    .build();
            HttpResponse<Void> response = httpClient.send(request, HttpResponse.BodyHandlers.discarding());
            if (response.statusCode() >= 200 && response.statusCode() < 300) {
                return CapabilityStatus.up("照片 AI 侧车可用");
            }
            return CapabilityStatus.down("照片 AI 健康检查状态码=" + response.statusCode());
        } catch (IOException | IllegalArgumentException exception) {
            return CapabilityStatus.down("照片 AI 侧车不可访问");
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            return CapabilityStatus.down("照片 AI 健康检查被中断");
        }
    }

    private URI readinessUri(String endpoint) {
        String normalized = endpoint == null ? "" : endpoint.trim();
        if (normalized.isBlank()) {
            throw new IllegalArgumentException("照片 AI 地址为空");
        }
        return URI.create(normalized.endsWith("/") ? normalized + "ready" : normalized + "/ready");
    }

}
