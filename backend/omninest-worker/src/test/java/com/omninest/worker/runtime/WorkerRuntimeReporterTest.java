package com.omninest.worker.runtime;

import com.sun.net.httpserver.HttpServer;
import com.omninest.common.runtime.WorkerRuntimeRegistry;
import com.omninest.common.runtime.WorkerRuntimeState;
import com.omninest.common.security.SafeUrlValidator;
import com.omninest.modules.photos.service.PhotosRuntimeConfigService;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.time.Duration;
import java.util.concurrent.atomic.AtomicReference;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;

/**
 * Worker 运行状态上报测试。
 *
 * @author OmniNest
 */
class WorkerRuntimeReporterTest {

    @Test
    void publishReportsDisabledPhotoAi() {
        WorkerRuntimeRegistry registry = Mockito.mock(WorkerRuntimeRegistry.class);
        PhotosRuntimeConfigService photosConfig = Mockito.mock(PhotosRuntimeConfigService.class);
        Mockito.when(photosConfig.isAiEnabled()).thenReturn(false);
        WorkerRuntimeProperties runtimeProperties = new WorkerRuntimeProperties();
        runtimeProperties.setInstanceId("worker-test");
        runtimeProperties.setHeartbeatTtl(Duration.ofSeconds(45));
        runtimeProperties.setProbeTimeout(Duration.ofMillis(200));
        WorkerRuntimeReporter reporter = new WorkerRuntimeReporter(
                registry,
                runtimeProperties,
                photosConfig,
                // 端点闸门由 OutboundEndpointRules 用例覆盖，本用例只验证上报链路。
                Mockito.mock(SafeUrlValidator.class)
        );

        reporter.publish();

        ArgumentCaptor<WorkerRuntimeState> stateCaptor = ArgumentCaptor.forClass(WorkerRuntimeState.class);
        Mockito.verify(registry).publish(stateCaptor.capture(), Mockito.eq(Duration.ofSeconds(45)));
        WorkerRuntimeState state = stateCaptor.getValue();
        Assertions.assertThat(state.instanceId()).isEqualTo("worker-test");
        Assertions.assertThat(state.reportedAt()).isNotNull();
        Assertions.assertThat(state.capability(WorkerRuntimeState.PHOTO_AI_CAPABILITY).status())
                .isEqualTo("DISABLED");
    }

    @Test
    void publishProbesPhotoAiReadinessEndpoint() throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        AtomicReference<String> requestedPath = new AtomicReference<>();
        server.createContext("/", exchange -> {
            requestedPath.set(exchange.getRequestURI().getPath());
            exchange.sendResponseHeaders(503, -1);
            exchange.close();
        });
        server.start();

        try {
            WorkerRuntimeRegistry registry = Mockito.mock(WorkerRuntimeRegistry.class);
            PhotosRuntimeConfigService photosConfig = Mockito.mock(PhotosRuntimeConfigService.class);
            Mockito.when(photosConfig.isAiEnabled()).thenReturn(true);
            Mockito.when(photosConfig.aiEndpoint())
                    .thenReturn("http://127.0.0.1:" + server.getAddress().getPort() + "/");
            WorkerRuntimeProperties runtimeProperties = new WorkerRuntimeProperties();
            runtimeProperties.setInstanceId("worker-test");
            runtimeProperties.setHeartbeatTtl(Duration.ofSeconds(45));
            runtimeProperties.setProbeTimeout(Duration.ofSeconds(2));
            WorkerRuntimeReporter reporter = new WorkerRuntimeReporter(
                    registry,
                    runtimeProperties,
                    photosConfig,
                    Mockito.mock(SafeUrlValidator.class)
            );

            reporter.publish();

            ArgumentCaptor<WorkerRuntimeState> stateCaptor = ArgumentCaptor.forClass(WorkerRuntimeState.class);
            Mockito.verify(registry).publish(stateCaptor.capture(), Mockito.eq(Duration.ofSeconds(45)));
            Assertions.assertThat(requestedPath).hasValue("/ready");
            Assertions.assertThat(stateCaptor.getValue()
                            .capability(WorkerRuntimeState.PHOTO_AI_CAPABILITY)
                            .status())
                    .isEqualTo("DOWN");
        } finally {
            server.stop(0);
        }
    }
}
