package com.omninest.common.ai;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.omninest.common.ai.ImageAnalysisGateway.ContentAnalysis;
import com.omninest.common.config.AiSidecarProperties;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.io.InputStream;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * 图像分析侧车客户端请求、解析与容量限制测试。
 *
 * @author OmniNest
 */
class AiSidecarClientTest {

    private HttpServer server;
    private String endpoint;
    private AiSidecarProperties properties;

    @BeforeEach
    void setUp() throws IOException {
        server = HttpServer.create(new InetSocketAddress(InetAddress.getLoopbackAddress(), 0), 0);
        server.start();
        endpoint = "http://127.0.0.1:" + server.getAddress().getPort();
        properties = new AiSidecarProperties();
        properties.setSecret("test-sidecar-secret");
        properties.setMaxImageBytes(1024);
        properties.setMaxResponseBytes(8192);
    }

    @AfterEach
    void tearDown() {
        server.stop(0);
    }

    @Test
    void shouldSendImageBytesInMultipartRequestWithHintAndSkipOcr() {
        byte[] imageBytes = new byte[]{1, 2, 3, 4, 5};
        AtomicReference<byte[]> requestBody = new AtomicReference<>();
        AtomicReference<String> requestContentType = new AtomicReference<>();
        AtomicReference<String> requestQuery = new AtomicReference<>();
        AtomicReference<String> requestToken = new AtomicReference<>();
        server.createContext("/analyze-content", exchange -> {
            requestContentType.set(exchange.getRequestHeaders().getFirst("Content-Type"));
            requestToken.set(exchange.getRequestHeaders().getFirst("X-OmniNest-Sidecar-Token"));
            requestQuery.set(exchange.getRequestURI().getQuery());
            requestBody.set(exchange.getRequestBody().readAllBytes());
            respond(exchange, """
                    {"schemaVersion":2,"pipelineVersion":"vision-v6-lightweight+ppocr-v4-onnx-v1",
                     "ocrPipelineVersion":"ppocr-v4-onnx-v1",
                     "observations":[{"namespace":"SUBJECT","code":"cat","confidence":0.91,
                     "source":"mobileclip2-s0-onnx","boxes":[]}],
                     "semanticTags":["橘猫"],"ocrText":"发票号码 12345"}
                    """);
        });
        AiSidecarClient client = new AiSidecarClient(properties);

        ContentAnalysis result = client.analyzeContent(
                imageBytes,
                "photo.jpg",
                "TEXT_GRAPHIC",
                false,
                endpoint,
                5
        );

        assertTrue(requestContentType.get().replace(" ", "").startsWith("multipart/form-data;boundary="));
        assertEquals("test-sidecar-secret", requestToken.get());
        assertTrue(requestQuery.get().contains("hint=TEXT_GRAPHIC"));
        assertTrue(requestQuery.get().contains("skipOcr=false"));
        String body = new String(requestBody.get(), StandardCharsets.ISO_8859_1);
        assertTrue(body.contains("name=\"image\""));
        assertTrue(body.contains("filename=\"photo.jpg\""));
        assertTrue(containsSequence(requestBody.get(), imageBytes));

        assertEquals(2, result.schemaVersion());
        assertEquals("vision-v6-lightweight+ppocr-v4-onnx-v1", result.pipelineVersion());
        assertEquals("ppocr-v4-onnx-v1", result.ocrPipelineVersion());
        assertEquals(1, result.observations().size());
        assertEquals("SUBJECT", result.observations().getFirst().namespace());
        assertEquals("cat", result.observations().getFirst().code());
        assertEquals(java.util.List.of("橘猫"), result.semanticTags());
        assertEquals("发票号码 12345", result.ocrText());
    }

    @Test
    void shouldStreamLargeMultipartBodyWithoutTruncation() {
        int imageSize = 1024 * 1024;
        byte[] imageBytes = new byte[imageSize];
        java.util.Arrays.fill(imageBytes, (byte) 0x5A);
        properties.setMaxImageBytes(imageSize);
        AtomicReference<byte[]> requestBody = new AtomicReference<>();
        server.createContext("/analyze-content", exchange -> {
            requestBody.set(exchange.getRequestBody().readAllBytes());
            respond(exchange, "{\"schemaVersion\":2,\"observations\":[],\"semanticTags\":[]}");
        });
        AiSidecarClient client = new AiSidecarClient(properties);

        client.analyzeContent(imageBytes, "large.jpg", "AUTO", false, endpoint, 5);

        assertThatBodyContainsImageBytes(requestBody.get(), imageBytes);
    }

    @Test
    void shouldRejectRequestWhenSidecarSecretIsMissing() {
        properties.setSecret(" ");
        AiSidecarClient client = new AiSidecarClient(properties);

        IllegalStateException exception = assertThrows(
                IllegalStateException.class,
                () -> client.analyzeContent(new byte[]{1, 2, 3}, "photo.jpg", "AUTO", false, endpoint, 5)
        );

        assertTrue(exception.getMessage().contains("认证密钥未配置"));
    }

    @Test
    void shouldRejectImageBeforeSendingWhenBytesExceedLimit() {
        properties.setMaxImageBytes(4);
        AiSidecarClient client = new AiSidecarClient(properties);

        assertThrows(
                IllegalArgumentException.class,
                () -> client.analyzeContent(new byte[]{1, 2, 3, 4, 5}, "photo.jpg", "AUTO", false, endpoint, 5)
        );
    }

    @Test
    void shouldRejectOversizedSidecarResponse() {
        properties.setMaxResponseBytes(8);
        server.createContext("/analyze-content", exchange -> respond(exchange, "{\"schemaVersion\":2}"));
        AiSidecarClient client = new AiSidecarClient(properties);

        assertThrows(
                IllegalStateException.class,
                () -> client.analyzeContent(new byte[]{1, 2, 3}, "photo.jpg", "AUTO", false, endpoint, 5)
        );
    }

    @Test
    void shouldKeepBoundedSidecarErrorDetails() {
        server.createContext("/analyze-content", exchange -> respond(
                exchange,
                422,
                "{\"detail\":\"missing multipart boundary\"}"
        ));
        AiSidecarClient client = new AiSidecarClient(properties);

        IllegalStateException exception = assertThrows(
                IllegalStateException.class,
                () -> client.analyzeContent(new byte[]{1, 2, 3}, "photo.jpg", "AUTO", false, endpoint, 5)
        );

        assertTrue(exception.getMessage().contains("422"));
        assertTrue(exception.getMessage().contains("missing multipart boundary"));
    }

    @Test
    void shouldProbeAndCacheRemotePipelineVersion() {
        AtomicInteger requests = new AtomicInteger();
        server.createContext("/ready", exchange -> {
            requests.incrementAndGet();
            respond(exchange, "{\"status\":\"ok\",\"pipelineVersion\":\"vision-v6-ram_plus_int8+ppocr-v4-onnx-v1\"}");
        });
        AiSidecarClient client = new AiSidecarClient(properties);

        assertEquals(
                "vision-v6-ram_plus_int8+ppocr-v4-onnx-v1",
                client.fetchRemotePipelineVersion(endpoint, 5)
        );
        assertEquals(
                "vision-v6-ram_plus_int8+ppocr-v4-onnx-v1",
                client.fetchRemotePipelineVersion(endpoint, 5)
        );
        assertEquals(1, requests.get());
    }

    @Test
    void shouldReturnNullWhenPipelineProbeFails() {
        server.createContext("/ready", exchange -> respond(exchange, 503, "{}"));
        AiSidecarClient client = new AiSidecarClient(properties);

        assertNull(client.fetchRemotePipelineVersion(endpoint, 5));
    }

    private void assertThatBodyContainsImageBytes(byte[] requestBody, byte[] imageBytes) {
        assertTrue(requestBody != null && requestBody.length > imageBytes.length);
        assertTrue(containsSequence(requestBody, imageBytes));
    }

    private void respond(HttpExchange exchange, String body) throws IOException {
        respond(exchange, 200, body);
    }

    private void respond(HttpExchange exchange, int status, String body) throws IOException {
        byte[] response = body.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "application/json");
        exchange.sendResponseHeaders(status, response.length);
        exchange.getResponseBody().write(response);
        exchange.close();
    }

    private boolean containsSequence(byte[] source, byte[] expected) {
        for (int offset = 0; offset <= source.length - expected.length; offset++) {
            boolean matches = true;
            for (int index = 0; index < expected.length; index++) {
                if (source[offset + index] != expected[index]) {
                    matches = false;
                    break;
                }
            }
            if (matches) {
                return true;
            }
        }
        return false;
    }
}
