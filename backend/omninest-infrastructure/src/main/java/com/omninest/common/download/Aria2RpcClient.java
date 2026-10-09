package com.omninest.common.download;

import com.omninest.common.config.Aria2Properties;
import com.omninest.common.json.JsonSupport;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.springframework.stereotype.Component;
import tools.jackson.databind.JsonNode;

/**
 * 通过 JSON-RPC 调用 Aria2 的离线下载适配器。
 *
 * @author OmniNest
 */
@Component
public class Aria2RpcClient implements OfflineDownloadGateway {
    private static final List<String> STATUS_FIELDS = List.of(
            "status",
            "totalLength",
            "completedLength",
            "downloadSpeed",
            "files",
            "bittorrent",
            "errorMessage"
    );

    private final Aria2Properties properties;
    private final HttpClient httpClient;

    /**
     * 根据 Aria2 配置创建 RPC 客户端。
     *
     * @param properties Aria2 运行配置
     */
    public Aria2RpcClient(Aria2Properties properties) {
        this.properties = properties;
        this.httpClient = HttpClient.newBuilder()
                .connectTimeout(Duration.ofSeconds(properties.getRpcTimeoutSeconds()))
                .build();
    }

    @Override
    public Path downloadRoot() {
        return Path.of(properties.getDownloadRoot());
    }

    @Override
    public int pollIntervalSeconds() {
        return properties.getPollIntervalSeconds();
    }

    @Override
    public Duration idleTimeout() {
        return Duration.ofMinutes(properties.getIdleTimeoutMinutes());
    }

    @Override
    public String submitUri(String uri, Map<String, Object> options) {
        List<Object> params = new ArrayList<>();
        params.add(List.of(uri));
        params.add(normalizeOptions(options));
        return callForString("aria2.addUri", params);
    }

    @Override
    public String submitTorrent(byte[] torrentBytes, Map<String, Object> options) {
        List<Object> params = new ArrayList<>();
        params.add(Base64.getEncoder().encodeToString(torrentBytes));
        params.add(List.of());
        params.add(normalizeOptions(options));
        return callForString("aria2.addTorrent", params);
    }

    @Override
    public TaskSnapshot queryStatus(String gid) {
        List<Object> params = new ArrayList<>();
        params.add(gid);
        params.add(STATUS_FIELDS);
        JsonNode result = call("aria2.tellStatus", params);
        return toTaskSnapshot(result);
    }

    @Override
    public void remove(String gid) {
        call("aria2.forceRemove", List.of(gid));
    }

    private Map<String, Object> normalizeOptions(Map<String, Object> options) {
        Map<String, Object> normalized = new LinkedHashMap<>();
        if (options != null) {
            normalized.putAll(options);
        }
        return normalized;
    }

    private String callForString(String method, List<Object> params) {
        JsonNode result = call(method, params);
        if (!result.isString() || result.asString().isBlank()) {
            throw new IllegalStateException("aria2 响应缺少结果");
        }
        return result.asString();
    }

    private JsonNode call(String method, List<Object> params) {
        List<Object> authorizedParams = authorize(params);
        Map<String, Object> request = new LinkedHashMap<>();
        request.put("jsonrpc", "2.0");
        request.put("id", UUID.randomUUID().toString());
        request.put("method", method);
        request.put("params", authorizedParams);

        HttpRequest httpRequest = HttpRequest.newBuilder(URI.create(properties.getRpcUrl()))
                .timeout(Duration.ofSeconds(properties.getRpcTimeoutSeconds()))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(JsonSupport.toJson(request), StandardCharsets.UTF_8))
                .build();
        try {
            HttpResponse<String> response = httpClient.send(
                    httpRequest,
                    HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8)
            );
            if (response.statusCode() >= 400) {
                throw new IllegalStateException("aria2 RPC 调用失败，状态码=" + response.statusCode());
            }
            if (response.body() == null || response.body().isBlank()) {
                throw new IllegalStateException("aria2 RPC 响应为空");
            }
            JsonNode body = JsonSupport.readTree(response.body());
            JsonNode error = body.path("error");
            if (error.isObject()) {
                String message = JsonSupport.textOrNull(error, "message");
                throw new IllegalStateException(message == null || message.isBlank()
                        ? "aria2 RPC 调用失败"
                        : message);
            }
            JsonNode rawResult = body.path("result");
            if (rawResult.isMissingNode() || rawResult.isNull()) {
                throw new IllegalStateException("aria2 RPC 响应缺少结果");
            }
            // addUri 等方法返回字符串 GID；tellStatus 等返回对象，调用方按需取文本或导航。
            return rawResult;
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("aria2 RPC 调用被中断", exception);
        } catch (Exception exception) {
            if (exception instanceof IllegalStateException illegalStateException) {
                throw illegalStateException;
            }
            throw new IllegalStateException("aria2 RPC 调用失败", exception);
        }
    }

    private List<Object> authorize(List<Object> params) {
        if (properties.getRpcSecret() == null || properties.getRpcSecret().isBlank()) {
            return params;
        }
        List<Object> authorized = new ArrayList<>();
        authorized.add("token:" + properties.getRpcSecret().trim());
        authorized.addAll(params);
        return authorized;
    }

    private static long parseLong(JsonNode value) {
        if (value == null || value.isMissingNode() || value.isNull()) {
            return 0L;
        }
        if (value.isNumber()) {
            return value.longValue();
        }
        String text = value.asString().trim();
        if (text.isEmpty()) {
            return 0L;
        }
        try {
            return Long.parseLong(text);
        } catch (NumberFormatException exception) {
            return 0L;
        }
    }

    static TaskSnapshot toTaskSnapshot(JsonNode result) {
        List<DownloadedFile> files = new ArrayList<>();
        JsonNode fileValues = result.path("files");
        if (fileValues.isArray()) {
            for (JsonNode value : fileValues) {
                if (!value.isObject()) {
                    continue;
                }
                String path = JsonSupport.textOrNull(value, "path");
                boolean selected = !"false".equalsIgnoreCase(JsonSupport.textOrNull(value, "selected"));
                files.add(new DownloadedFile(path, selected));
            }
        }
        return new TaskSnapshot(
                JsonSupport.textOrNull(result, "status"),
                parseLong(result.path("totalLength")),
                parseLong(result.path("completedLength")),
                parseLong(result.path("downloadSpeed")),
                files,
                resolveDisplayName(result.path("bittorrent"), files),
                JsonSupport.textOrNull(result, "errorMessage")
        );
    }

    private static String resolveDisplayName(JsonNode bittorrent, List<DownloadedFile> files) {
        if (bittorrent != null && bittorrent.isObject()) {
            JsonNode info = bittorrent.path("info");
            if (info.isObject()) {
                String name = JsonSupport.textOrNull(info, "name");
                if (name != null && !name.isBlank()) {
                    return name.trim();
                }
            }
        }
        if (files.isEmpty()) {
            return null;
        }
        String path = files.getFirst().path();
        if (path == null || path.isBlank()) {
            return null;
        }
        return Path.of(path).getFileName().toString();
    }
}
