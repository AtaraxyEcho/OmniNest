package com.omninest.modules.video.service;

import java.io.IOException;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * FFmpeg 运行位置探测：优先使用后端容器内自带的 ffmpeg，其次回退到
 * {@code docker exec omninest-ffmpeg}。
 *
 * <p>生产后端镜像已安装 ffmpeg，但没有 docker CLI 与 docker.sock；转码、字幕提取
 * 与实时流若硬编码 docker exec 会 100% 失败。探测延迟到首次使用，避免应用启动时
 * 阻塞在子进程超时上。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
public class VideoFfmpegRuntime {

    public static final String DOCKER_CONTAINER = "omninest-ffmpeg";
    private static final Duration PROBE_TIMEOUT = Duration.ofSeconds(15);

    /**
     * ffmpeg 运行方式。
     */
    public enum Mode { LOCAL, DOCKER, DISABLED }

    private final VideoProcessExecutor processExecutor;
    private volatile Mode mode;

    public VideoFfmpegRuntime(VideoProcessExecutor processExecutor) {
        this.processExecutor = processExecutor;
    }

    /**
     * 返回探测结果；首次调用时执行探测。
     *
     * @return 运行方式
     */
    public Mode mode() {
        Mode current = mode;
        if (current != null) {
            return current;
        }
        synchronized (this) {
            if (mode == null) {
                mode = detect();
            }
            return mode;
        }
    }

    public boolean isDocker() {
        return mode() == Mode.DOCKER;
    }

    public boolean isDisabled() {
        return mode() == Mode.DISABLED;
    }

    private Mode detect() {
        if (canRun(List.of("ffmpeg", "-version"))) {
            log.info("ffmpeg 可用（本地），视频转码与实时流已启用");
            return Mode.LOCAL;
        }
        if (canRun(List.of("docker", "exec", DOCKER_CONTAINER, "ffmpeg", "-version"))) {
            log.info("ffmpeg 可用（Docker 容器 {}），视频转码与实时流已启用", DOCKER_CONTAINER);
            return Mode.DOCKER;
        }
        log.warn("ffmpeg 不可用，视频转码、字幕提取与实时音频流将不可用。"
                + "请在后端镜像安装 ffmpeg 或启动 ffmpeg 容器并授予 docker CLI");
        return Mode.DISABLED;
    }

    private boolean canRun(List<String> command) {
        try {
            VideoProcessExecutor.Result result = processExecutor.execute(command, PROBE_TIMEOUT);
            return result.succeeded();
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            return false;
        } catch (IOException exception) {
            return false;
        }
    }

    /**
     * 构建本地模式的 ffmpeg 命令。
     *
     * <p>{@code -protocol_whitelist} 必须在 {@code -i} 之前：输入是 HTTP 预签名地址时
     * 只放行 HTTP 系列，输入是本地路径时只放行文件协议，避免媒体内容里内嵌的
     * {@code concat:}/{@code file:} 引用把后端容器当作文件/网络跳板。</p>
     *
     * @param input ffmpeg 输入（URL 或本地路径）
     * @param args 输入之后的 ffmpeg 参数
     * @return 完整命令
     */
    public List<String> localCommand(String input, List<String> args) {
        List<String> command = new ArrayList<>();
        command.add("ffmpeg");
        command.add("-y");
        command.add("-protocol_whitelist");
        command.add(protocolWhitelist(input));
        command.add("-i");
        command.add(input);
        command.addAll(args);
        return command;
    }

    /**
     * 判断输入需要的协议白名单。
     *
     * @param input ffmpeg 输入
     * @return 协议白名单
     */
    public String protocolWhitelist(String input) {
        if (input == null) {
            return "file,crypto,data";
        }
        String lower = input.toLowerCase(Locale.ROOT);
        return lower.startsWith("http://") || lower.startsWith("https://")
                ? "http,https,tcp,tls"
                : "file,crypto,data";
    }

    /**
     * 为实时流构建带容器内 PID 记录的 docker exec 命令。
     *
     * <p>包装 shell 记录 {@code $$} 后 exec ffmpeg：destroy 客户端进程不会杀掉容器内
     * 的 ffmpeg，收尾时可按 PID 文件精确终止，避免拖动进度条累积孤儿进程。</p>
     *
     * @param marker 本次流的唯一标记
     * @param ffmpegArgs ffmpeg 参数（含程序名之后的全部参数）
     * @return 完整命令
     */
    public List<String> dockerStreamCommand(String marker, List<String> ffmpegArgs) {
        String pidFile = pidFile(marker);
        String script = "echo $$ > " + pidFile + "; exec ffmpeg \"$@\"";
        List<String> command = new ArrayList<>();
        command.add("docker");
        command.add("exec");
        command.add(DOCKER_CONTAINER);
        command.add("sh");
        command.add("-c");
        command.add(script);
        command.add("ffmpeg");
        command.addAll(ffmpegArgs);
        return command;
    }

    /**
     * 终止容器内由 {@link #dockerStreamCommand} 启动的 ffmpeg。
     *
     * @param marker 流标记
     * @return 终止命令执行器；调用方负责执行
     */
    public List<String> dockerKillCommand(String marker) {
        String pidFile = pidFile(marker);
        String script = "pid=$(cat " + pidFile + " 2>/dev/null); "
                + "if [ -n \"$pid\" ]; then kill -9 \"$pid\" 2>/dev/null; fi; rm -f " + pidFile;
        return List.of("docker", "exec", DOCKER_CONTAINER, "sh", "-c", script);
    }

    public String newMarker() {
        return UUID.randomUUID().toString();
    }

    private String pidFile(String marker) {
        return "/tmp/omninest-stream-" + marker + ".pid";
    }
}
