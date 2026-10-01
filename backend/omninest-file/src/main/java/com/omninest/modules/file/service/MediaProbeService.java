package com.omninest.modules.file.service;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import com.omninest.modules.file.dto.FileMediaInfoDto;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.concurrent.TimeUnit;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 媒体元数据探测服务：对可寻址内容 URL 执行 ffprobe，解析时长与分辨率。
 *
 * <p>结果按内容地址缓存（同一内容版本只探测一次），任何失败（工具缺失、
 * 超时、解析异常）都收敛为空结果，绝不让探测失败影响业务请求。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
public class MediaProbeService {

    private static final Duration PROCESS_TIMEOUT = Duration.ofSeconds(10);
    private static final int MAX_OUTPUT_BYTES = 1024 * 1024;

    /** 空结果单例，避免失败路径重复分配。 */
    static final FileMediaInfoDto EMPTY = new FileMediaInfoDto(null, null, null);

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final Cache<String, FileMediaInfoDto> cache = Caffeine.newBuilder()
            .maximumSize(500)
            .expireAfterWrite(2, TimeUnit.HOURS)
            .build();

    /**
     * 探测媒体内容；contentKey 为内容对象唯一键（含版本），用于缓存。
     *
     * @param contentKey 内容缓存键
     * @param contentUrl 可直接访问的内容地址（presigned URL）
     * @return 媒体元数据，失败为空对象
     */
    public FileMediaInfoDto probe(String contentKey, String contentUrl) {
        return cache.get(contentKey, key -> probeOnce(contentUrl));
    }

    private FileMediaInfoDto probeOnce(String contentUrl) {
        try {
            String json = runFfprobe(contentUrl);
            return parseProbeJson(json);
        } catch (IOException | InterruptedException e) {
            Thread.currentThread().interrupt();
            log.warn("媒体探测失败: {}", e.getMessage());
            return EMPTY;
        } catch (RuntimeException e) {
            log.warn("媒体探测解析失败: {}", e.getMessage());
            return EMPTY;
        }
    }

    private String runFfprobe(String contentUrl) throws IOException, InterruptedException {
        Process process = new ProcessBuilder(
                "ffprobe",
                "-v", "quiet",
                "-print_format", "json",
                "-show_format",
                "-show_streams",
                contentUrl)
                .redirectErrorStream(true)
                .start();
        try {
            byte[] output;
            try (var input = process.getInputStream()) {
                output = input.readNBytes(MAX_OUTPUT_BYTES);
            }
            if (!process.waitFor(PROCESS_TIMEOUT.toMillis(), TimeUnit.MILLISECONDS)) {
                process.destroyForcibly();
                throw new IOException("ffprobe 超时");
            }
            return new String(output, StandardCharsets.UTF_8);
        } catch (IOException e) {
            process.destroyForcibly();
            throw e;
        }
    }

    /**
     * 解析 ffprobe JSON 输出：时长取 format.duration；宽高优先取首个
     * 视频流（图片探测同样落在视频流位置），回退 format 级别字段。
     */
    FileMediaInfoDto parseProbeJson(String json) {
        try {
            JsonNode root = objectMapper.readTree(json);
            Double duration = null;
            JsonNode format = root.get("format");
            if (format != null && format.hasNonNull("duration")) {
                duration = Double.parseDouble(format.get("duration").asText());
            }
            Integer width = null;
            Integer height = null;
            if (root.has("streams")) {
                for (JsonNode stream : root.get("streams")) {
                    if ("video".equals(stream.path("codec_type").asText())) {
                        width = stream.hasNonNull("width") ? stream.get("width").asInt() : null;
                        height = stream.hasNonNull("height") ? stream.get("height").asInt() : null;
                        if (duration == null && stream.hasNonNull("duration")) {
                            duration = Double.parseDouble(stream.get("duration").asText());
                        }
                        break;
                    }
                }
            }
            return new FileMediaInfoDto(duration, width, height);
        } catch (RuntimeException e) {
            return EMPTY;
        }
    }

}
