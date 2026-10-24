package com.omninest.modules.video.service;

import java.io.IOException;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * FFmpeg 运行探测：后端镜像内置 ffmpeg，所有转码、探测与实时流都在本机执行。
 *
 * <p>探测延迟到首次使用，避免应用启动时阻塞在子进程超时上。生产编排不再维护
 * 独立的 ffmpeg 容器与 docker socket：后者需要给后端挂 docker CLI，反而扩大权限面。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
public class VideoFfmpegRuntime {

    private static final Duration PROBE_TIMEOUT = Duration.ofSeconds(15);

    /**
     * ffmpeg 运行方式。
     */
    public enum Mode { LOCAL, DISABLED }

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

    public boolean isDisabled() {
        return mode() == Mode.DISABLED;
    }

    private Mode detect() {
        if (canRun(List.of("ffmpeg", "-version"))) {
            log.info("ffmpeg 可用（本地），视频转码与实时流已启用");
            return Mode.LOCAL;
        }
        log.warn("ffmpeg 不可用，视频转码、字幕提取与实时音频流将不可用。"
                + "请在后端镜像安装 ffmpeg。");
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
     * <p>本地转码输入已由调用方落到受控临时文件，只允许 file/crypto/data；
     * HTTP 分支仅保留给实时播放（需要 Range/跳转，无法整文件落盘）。</p>
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
}
