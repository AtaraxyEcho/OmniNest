package com.omninest.common.download;

import com.alibaba.fastjson2.JSON;
import com.alibaba.fastjson2.JSONArray;
import com.alibaba.fastjson2.JSONObject;
import com.omninest.common.config.Aria2Properties;
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
        JSONObject result = call("aria2.tellStatus", params);
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
        JSONObject result = call(method, params);
        String value = result.getString("result");
        if (value == null || value.isBlank()) {
            throw new IllegalStateException("aria2 响应缺少结果");
        }
        return value;
    }

    private JSONObject call(String method, List<Object> params) {
        List<Object> authorizedParams = authorize(params);
        Map<String, Object> request = new LinkedHashMap<>();
        request.put("jsonrpc", "2.0");
        request.put("id", UUID.randomUUID().toString());
        request.put("method", method);
        request.put("params", authorizedParams);

        HttpRequest httpRequest = HttpRequest.newBuilder(URI.create(properties.getRpcUrl()))
                .timeout(Duration.ofSeconds(properties.getRpcTimeoutSeconds()))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(JSON.toJSONString(request), StandardCharsets.UTF_8))
                .build();
        try {
            HttpResponse<String> response = httpClient.send(
                    httpRequest,
                    HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8)
            );
            if (response.statusCode() >= 400) {
                throw new IllegalStateException("aria2 RPC 调用失败，状态码=" + response.statusCode());
            }
            JSONObject body = JSON.parseObject(response.body());
            if (body == null) {
                throw new IllegalStateException("aria2 RPC 响应为空");
            }
            JSONObject error = body.getJSONObject("error");
            if (error != null) {
                String message = error.getString("message");
                throw new IllegalStateException(message == null || message.isBlank()
                        ? "aria2 RPC 调用失败"
                        : message);
            }
            Object rawResult = body.get("result");
            // addUri 等方法返回字符串 GID；tellStatus 等返回对象。不可对字符串调 getJSONObject。
            if (rawResult instanceof String stringResult) {
                JSONObject wrapper = new JSONObject();
                wrapper.put("result", stringResult);
                return wrapper;
            }
            if (rawResult instanceof JSONObject resultObject) {
                return resultObject;
            }
            if (rawResult == null) {
                throw new IllegalStateException("aria2 RPC 响应缺少结果");
            }
            JSONObject wrapper = new JSONObject();
            wrapper.put("result", rawResult);
            return wrapper;
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

    private static long parseLong(Object value) {
        if (value == null) {
            return 0L;
        }
        if (value instanceof Number number) {
            return number.longValue();
        }
        String text = value.toString().trim();
        if (text.isEmpty()) {
            return 0L;
        }
        try {
            return Long.parseLong(text);
        } catch (NumberFormatException exception) {
            return 0L;
        }
    }

    static TaskSnapshot toTaskSnapshot(JSONObject result) {
        List<DownloadedFile> files = new ArrayList<>();
        JSONArray fileValues = result.getJSONArray("files");
        if (fileValues != null) {
            for (Object value : fileValues) {
                if (!(value instanceof JSONObject file)) {
                    continue;
                }
                String path = file.getString("path");
                boolean selected = !"false".equalsIgnoreCase(file.getString("selected"));
                files.add(new DownloadedFile(path, selected));
            }
        }
        return new TaskSnapshot(
                result.getString("status"),
                parseLong(result.get("totalLength")),
                parseLong(result.get("completedLength")),
                parseLong(result.get("downloadSpeed")),
                files,
                resolveDisplayName(result.getJSONObject("bittorrent"), files),
                result.getString("errorMessage")
        );
    }

    private static String resolveDisplayName(JSONObject bittorrent, List<DownloadedFile> files) {
        if (bittorrent != null) {
            JSONObject info = bittorrent.getJSONObject("info");
            if (info != null) {
                String name = info.getString("name");
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
