package com.omninest.modules.file.service;

import tools.jackson.databind.JsonNode;
import tools.jackson.databind.ObjectMapper;
import com.github.benmanes.caffeine.cache.Cache;
import com.github.benmanes.caffeine.cache.Caffeine;
import com.omninest.modules.file.dto.FileMediaInfoDto;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.List;
import java.util.concurrent.TimeUnit;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 媒体元数据探测服务：对**本地探测输入**执行 ffprobe，解析时长与分辨率。
 *
 * <p>输入形态是安全边界的一部分：给 ffprobe 地址时，媒体内容里内嵌的远程引用会被它自己跟随，
 * 那批地址不经过任何校验；本地文件输入下 ffmpeg 的默认协议集不含远程协议。
 * 探测输入的取法见 {@link MediaProbeSourceStager}。
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
    static final int MAX_OUTPUT_BYTES = 1024 * 1024;

    /** 空结果单例，避免失败路径重复分配。 */
    static final FileMediaInfoDto EMPTY = new FileMediaInfoDto(null, null, null);

    private final ObjectMapper objectMapper = new ObjectMapper();
    private final Cache<String, FileMediaInfoDto> cache = Caffeine.newBuilder()
            .maximumSize(500)
            .expireAfterWrite(2, TimeUnit.HOURS)
            .build();
    private final ProcessStarter processStarter;

    public MediaProbeService() {
        this(MediaProbeService::startFfprobe);
    }

    /** 隔离系统进程 API 的测试边界，与 video 模块的外部进程执行器同一形态。 */
    MediaProbeService(ProcessStarter processStarter) {
        this.processStarter = processStarter;
    }

    /**
     * 探测媒体内容；contentKey 为内容对象唯一键（含版本），用于缓存。
     *
     * @param contentKey 内容缓存键
     * @param probeInput 本地探测输入路径
     * @return 媒体元数据，失败为空对象
     */
    public FileMediaInfoDto probe(String contentKey, Path probeInput) {
        return cache.get(contentKey, key -> probeOnce(probeInput));
    }

    private FileMediaInfoDto probeOnce(Path probeInput) {
        try {
            String json = runFfprobe(probeInput);
            return parseProbeJson(json);
        } catch (InterruptedException e) {
            // 中断位只在真被中断时回填：以前 IOException（工具缺失、超时）也一并置位，
            // 会把池化线程打上中断标记，后续 JDBC/HTTP 立刻抛 InterruptedException。
            Thread.currentThread().interrupt();
            log.warn("媒体探测被中断: {}", e.getMessage());
            return EMPTY;
        } catch (IOException e) {
            log.warn("媒体探测失败: {}", e.getMessage());
            return EMPTY;
        } catch (RuntimeException e) {
            log.warn("媒体探测解析失败: {}", e.getMessage());
            return EMPTY;
        }
    }

    /**
     * 执行 ffprobe 并取回 JSON 输出。
     *
     * <p>输出重定向到临时文件而不是读管道：先 {@code readNBytes} 再 {@code waitFor(timeout)}
     * 的写法会阻塞在读上，进程挂起时超时根本到不了点；反过来先等再读，未取的管道又可能把
     * 子进程堵满。落临时文件两边都不占。
     *
     * @param probeInput 本地探测输入路径
     * @return ffprobe 的 JSON 输出（超过上限按上限截断）
     * @throws IOException        进程启动失败、超时或读输出失败
     * @throws InterruptedException 等待期间线程被中断
     */
    String runFfprobe(Path probeInput) throws IOException, InterruptedException {
        Path outputFile = Files.createTempFile("omninest-ffprobe-", ".json");
        Process process = null;
        try {
            process = processStarter.start(List.of(
                    "ffprobe",
                    "-v", "quiet",
                    "-print_format", "json",
                    "-show_format",
                    "-show_streams",
                    probeInput.toAbsolutePath().normalize().toString()), outputFile);
            // 子进程不读标准输入，但管道要关，否则每次探测都留下一个空闲 fd。
            process.getOutputStream().close();
            if (!process.waitFor(PROCESS_TIMEOUT.toMillis(), TimeUnit.MILLISECONDS)) {
                throw new IOException("ffprobe 超时");
            }
            try (InputStream input = Files.newInputStream(outputFile)) {
                return new String(input.readNBytes(MAX_OUTPUT_BYTES), StandardCharsets.UTF_8);
            }
        } finally {
            // 进程起不来时也要删掉已经建好的临时文件，否则每次探测都留一个空文件。
            if (process != null && process.isAlive()) {
                process.destroyForcibly();
            }
            try {
                Files.deleteIfExists(outputFile);
            } catch (IOException e) {
                log.debug("ffprobe 临时输出清理失败: {}", e.getMessage());
            }
        }
    }

    private static Process startFfprobe(List<String> command, Path outputFile) throws IOException {
        return new ProcessBuilder(command)
                .redirectErrorStream(true)
                .redirectOutput(outputFile.toFile())
                .start();
    }

    /**
     * 创建 ffprobe 进程，便于隔离系统进程 API 的测试边界。
     */
    @FunctionalInterface
    interface ProcessStarter {
        /**
         * 启动命令，并把合并后的标准输出与错误输出写入 {@code outputFile}。
         *
         * @param command 外部命令及参数
         * @param outputFile 输出落点
         * @return 已启动的系统进程
         * @throws IOException 进程启动失败
         */
        Process start(List<String> command, Path outputFile) throws IOException;
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
                duration = Double.parseDouble(format.get("duration").asString());
            }
            Integer width = null;
            Integer height = null;
            if (root.has("streams")) {
                for (JsonNode stream : root.get("streams")) {
                    if ("video".equals(stream.path("codec_type").asString())) {
                        width = stream.hasNonNull("width") ? stream.get("width").asInt() : null;
                        height = stream.hasNonNull("height") ? stream.get("height").asInt() : null;
                        if (duration == null && stream.hasNonNull("duration")) {
                            duration = Double.parseDouble(stream.get("duration").asString());
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
