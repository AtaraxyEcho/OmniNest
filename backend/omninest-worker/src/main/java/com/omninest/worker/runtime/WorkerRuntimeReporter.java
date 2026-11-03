package com.omninest.worker.runtime;

import com.omninest.common.runtime.WorkerRuntimeRegistry;
import com.omninest.common.security.OutboundEndpointRules;
import com.omninest.common.security.SafeUrlValidator;
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
    private final SafeUrlValidator safeUrlValidator;
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

    /**
     * 构造侧车就绪探针地址，并按配置基址规则复核。
     *
     * <p>探针虽不需要鉴权，但仍然是服务端主动出站：只校验 HTTP 状态码而不校验目标，
     * 配置里写成 {@code file:}/{@code http://169.254.169.254} 或带查询串时，
     * 探测本身就会成为 SSRF 通道。这里统一走 {@link OutboundEndpointRules}，
     * 与 {@code AiSidecarClient} 保持同一判据。</p>
     */
    private URI readinessUri(String endpoint) {
        String normalized = endpoint == null ? "" : endpoint.trim();
        if (normalized.isBlank()) {
            throw new IllegalArgumentException("照片 AI 地址为空");
        }
        while (normalized.endsWith("/")) {
            normalized = normalized.substring(0, normalized.length() - 1);
        }
        URI target = URI.create(normalized + "/ready");
        return OutboundEndpointRules.requireConfiguredEndpoint(normalized, target, safeUrlValidator);
    }

}
