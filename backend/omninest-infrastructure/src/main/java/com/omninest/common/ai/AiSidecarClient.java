package com.omninest.common.ai;

import com.omninest.common.ai.ImageAnalysisGateway.BoundingBox;
import com.omninest.common.ai.ImageAnalysisGateway.ContentAnalysis;
import com.omninest.common.ai.ImageAnalysisGateway.ContentObservation;
import com.omninest.common.config.AiSidecarProperties;
import com.omninest.common.json.JsonSupport;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import lombok.extern.slf4j.Slf4j;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.MediaType;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.stereotype.Component;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestClient;
import org.springframework.web.util.UriComponentsBuilder;
import tools.jackson.databind.JsonNode;

/**
 * 图像分析侧车服务 HTTP 客户端。
 *
 * <p>图片请求通过标准 multipart 编码器发送，响应按配置限制最大字节数。
 *
 * @author OmniNest
 */
@Slf4j
@Component
public class AiSidecarClient implements ImageAnalysisGateway {

    private static final int BUFFER_SIZE = 8192;
    private static final int MAX_ERROR_SUMMARY_CHARS = 512;
    private static final long PIPELINE_VERSION_CACHE_MILLIS = 60_000L;
    private static final String SIDECAR_TOKEN_HEADER = "X-OmniNest-Sidecar-Token";

    private final AiSidecarProperties properties;
    private final HttpClient httpClient;
    private final Object pipelineVersionLock = new Object();
    private volatile PipelineVersionCache pipelineVersionCache;

    /**
     * 创建图像分析侧车客户端。
     *
     * @param properties 图像分析侧车配置
     */
    public AiSidecarClient(AiSidecarProperties properties) {
        this.properties = properties;
        this.httpClient = HttpClient.newBuilder()
                .version(HttpClient.Version.HTTP_1_1)
                .connectTimeout(Duration.ofSeconds(properties.getTimeoutSeconds()))
                .followRedirects(HttpClient.Redirect.NEVER)
                .build();
        log.info("AiSidecarClient 初始化: endpoint={}", properties.getEndpoint());
    }

    /**
     * 返回允许发送到图像分析侧车的最大图片字节数。
     *
     * @return 最大图片字节数
     */
    @Override
    public long maxImageBytes() {
        return properties.getMaxImageBytes();
    }

    @Override
    public String fetchRemotePipelineVersion(String endpoint, int timeoutSeconds) {
        String normalizedEndpoint = normalizeEndpoint(endpoint);
        if (normalizedEndpoint.isEmpty()) {
            return null;
        }
        long now = System.currentTimeMillis();
        PipelineVersionCache cached = pipelineVersionCache;
        if (cached != null
                && cached.endpoint().equals(normalizedEndpoint)
                && now - cached.fetchedAtMillis() < PIPELINE_VERSION_CACHE_MILLIS) {
            return cached.version();
        }
        synchronized (pipelineVersionLock) {
            cached = pipelineVersionCache;
            now = System.currentTimeMillis();
            if (cached != null
                    && cached.endpoint().equals(normalizedEndpoint)
                    && now - cached.fetchedAtMillis() < PIPELINE_VERSION_CACHE_MILLIS) {
                return cached.version();
            }
            String version = probePipelineVersion(normalizedEndpoint, timeoutSeconds);
            pipelineVersionCache = new PipelineVersionCache(
                    normalizedEndpoint,
                    version,
                    System.currentTimeMillis()
            );
            return version;
        }
    }

    @Override
    public ContentAnalysis analyzeContent(
            byte[] imageBytes,
            String filename,
            String hint,
            boolean skipOcr,
            String endpoint,
            int timeoutSeconds
    ) {
        if (imageBytes == null || imageBytes.length == 0) {
            throw new IllegalArgumentException("图像分析输入不能为空");
        }
        if (imageBytes.length > properties.getMaxImageBytes()) {
            throw new IllegalArgumentException("图像分析输入大小超出限制");
        }
        String normalizedEndpoint = requireEndpoint(endpoint);
        URI uri = UriComponentsBuilder.fromUriString(normalizedEndpoint)
                .path("/analyze-content")
                .queryParam("hint", hint == null || hint.isBlank() ? "AUTO" : hint)
                .queryParam("skipOcr", skipOcr)
                .build()
                .encode()
                .toUri();
        MultiValueMap<String, Object> multipartBody = new LinkedMultiValueMap<>();
        multipartBody.add("image", new InMemoryImageResource(imageBytes, safeFilename(filename)));
        String responseBody = sendMultipart(uri, multipartBody, timeoutSeconds);
        return parseContentAnalysis(JsonSupport.readTree(responseBody));
    }

    private String probePipelineVersion(String endpoint, int timeoutSeconds) {
        try {
            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(endpoint + "/ready"))
                    .timeout(Duration.ofSeconds(Math.clamp(timeoutSeconds, 1, 30)))
                    .headers(tokenHeaders())
                    .GET()
                    .build();
            String responseBody = sendRequest(request);
            String version = JsonSupport.readTree(responseBody).path("pipelineVersion").asString(null);
            return version == null || version.isBlank() ? null : version.trim();
        } catch (RuntimeException exception) {
            log.warn("侧车流水线版本探测失败: endpoint={}, errorType={}",
                    endpoint, exception.getClass().getSimpleName());
            return null;
        }
    }

    private ContentAnalysis parseContentAnalysis(JsonNode object) {
        List<ContentObservation> observations = new ArrayList<>();
        for (JsonNode observation : object.path("observations")) {
            String namespace = observation.path("namespace").asString(null);
            String code = observation.path("code").asString(null);
            float confidence = (float) observation.path("confidence").asDouble();
            if (namespace == null || namespace.isBlank()
                    || code == null || code.isBlank()
                    || !Float.isFinite(confidence)) {
                continue;
            }
            observations.add(new ContentObservation(
                    namespace,
                    code,
                    confidence,
                    observation.path("source").asString(null),
                    parseBoundingBoxes(observation.path("boxes"))
            ));
        }
        List<String> semanticTags = new ArrayList<>();
        for (JsonNode tag : object.path("semanticTags")) {
            String value = tag.asString(null);
            if (value != null && !value.isBlank()) {
                semanticTags.add(value.trim());
            }
        }
        String ocrText = object.path("ocrText").asString(null);
        if (ocrText != null && ocrText.isBlank()) {
            ocrText = null;
        }
        return new ContentAnalysis(
                Math.max(1, object.path("schemaVersion").asInt()),
                object.path("pipelineVersion").asString(null),
                object.path("ocrPipelineVersion").asString(null),
                observations,
                semanticTags,
                ocrText
        );
    }

    private List<BoundingBox> parseBoundingBoxes(JsonNode boxesArray) {
        if (!boxesArray.isArray()) {
            return List.of();
        }
        List<BoundingBox> boxes = new ArrayList<>();
        for (JsonNode box : boxesArray) {
            float x = (float) box.path("x").asDouble();
            float y = (float) box.path("y").asDouble();
            float width = (float) box.path("width").asDouble();
            float height = (float) box.path("height").asDouble();
            if (Float.isFinite(x) && Float.isFinite(y)
                    && Float.isFinite(width) && Float.isFinite(height)
                    && width > 0 && height > 0) {
                boxes.add(new BoundingBox(x, y, width, height));
            }
        }
        return List.copyOf(boxes);
    }

    private String sendMultipart(URI uri, MultiValueMap<String, Object> multipartBody, int timeoutSeconds) {
        JdkClientHttpRequestFactory requestFactory = new JdkClientHttpRequestFactory(httpClient);
        requestFactory.setReadTimeout(Duration.ofSeconds(timeoutSeconds));
        try {
            return RestClient.builder()
                    .requestFactory(requestFactory)
                    .build()
                    .post()
                    .uri(uri)
                    .headers(headers -> headers.add(SIDECAR_TOKEN_HEADER, requireSecret()))
                    .contentType(MediaType.MULTIPART_FORM_DATA)
                    .body(multipartBody)
                    .exchange((request, response) -> {
                        String responseBody;
                        try (InputStream body = response.getBody()) {
                            responseBody = readBoundedUtf8(body, properties.getMaxResponseBytes());
                        }
                        requireSuccessfulResponse(response.getStatusCode().value(), responseBody);
                        return responseBody;
                    });
        } catch (IllegalStateException exception) {
            throw exception;
        } catch (Exception exception) {
            throw new IllegalStateException("图像分析侧车调用失败", exception);
        }
    }

    private String sendRequest(HttpRequest request) {
        try {
            HttpResponse<InputStream> response = httpClient.send(
                    request,
                    HttpResponse.BodyHandlers.ofInputStream()
            );
            String responseBody;
            try (InputStream body = response.body()) {
                responseBody = readBoundedUtf8(body, properties.getMaxResponseBytes());
            }
            requireSuccessfulResponse(response.statusCode(), responseBody);
            return responseBody;
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("图像分析侧车调用被中断", exception);
        } catch (IllegalStateException exception) {
            throw exception;
        } catch (Exception exception) {
            throw new IllegalStateException("图像分析侧车调用失败", exception);
        }
    }

    private String[] tokenHeaders() {
        String secret = properties.getSecret();
        if (secret == null || secret.isBlank()) {
            return new String[0];
        }
        return new String[]{SIDECAR_TOKEN_HEADER, secret};
    }

    private String requireSecret() {
        String secret = properties.getSecret();
        if (secret == null || secret.isBlank()) {
            throw new IllegalStateException("图像分析侧车认证密钥未配置");
        }
        return secret;
    }

    private String requireEndpoint(String endpoint) {
        String normalizedEndpoint = normalizeEndpoint(endpoint);
        if (normalizedEndpoint.isEmpty()) {
            throw new IllegalArgumentException("图像分析侧车地址不能为空");
        }
        return normalizedEndpoint;
    }

    private String normalizeEndpoint(String endpoint) {
        if (endpoint == null) {
            return "";
        }
        String normalized = endpoint.trim();
        while (normalized.endsWith("/")) {
            normalized = normalized.substring(0, normalized.length() - 1);
        }
        return normalized;
    }

    private String safeFilename(String filename) {
        if (filename == null || filename.isBlank()) {
            return "image.jpg";
        }
        String sanitized = filename.replaceAll("[\\r\\n\\\"\\\\/]", "_").trim();
        return sanitized.isEmpty() ? "image.jpg" : sanitized;
    }

    private void requireSuccessfulResponse(int statusCode, String responseBody) {
        if (statusCode < 400) {
            return;
        }
        String responseSummary = summarizeErrorResponse(responseBody);
        throw new IllegalStateException(
                "图像分析侧车调用失败，状态码=" + statusCode
                        + (responseSummary.isEmpty() ? "" : "，响应摘要=" + responseSummary)
        );
    }

    private String readBoundedUtf8(InputStream input, int maxBytes) throws IOException {
        if (maxBytes <= 0) {
            throw new IllegalStateException("图像分析响应大小限制无效");
        }
        ByteArrayOutputStream output = new ByteArrayOutputStream(Math.min(maxBytes, BUFFER_SIZE));
        byte[] buffer = new byte[BUFFER_SIZE];
        int totalRead = 0;
        int read;
        while ((read = input.read(buffer)) != -1) {
            totalRead += read;
            if (totalRead > maxBytes) {
                throw new IllegalStateException("图像分析侧车响应超过大小限制");
            }
            output.write(buffer, 0, read);
        }
        return output.toString(StandardCharsets.UTF_8);
    }

    private String summarizeErrorResponse(String responseBody) {
        if (responseBody == null || responseBody.isBlank()) {
            return "";
        }
        String normalized = responseBody.replaceAll("\\s+", " ").trim();
        if (normalized.length() <= MAX_ERROR_SUMMARY_CHARS) {
            return normalized;
        }
        return normalized.substring(0, MAX_ERROR_SUMMARY_CHARS);
    }

    private record PipelineVersionCache(String endpoint, String version, long fetchedAtMillis) {
    }

    /**
     * 内存图片 multipart 资源；文件名来自调用方受控值。
     */
    private static final class InMemoryImageResource extends ByteArrayResource {
        private final String filename;

        private InMemoryImageResource(byte[] byteArray, String filename) {
            super(byteArray);
            this.filename = filename;
        }

        @Override
        public String getFilename() {
            return filename;
        }
    }
}
