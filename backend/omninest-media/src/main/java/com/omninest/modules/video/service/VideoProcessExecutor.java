package com.omninest.modules.video.service;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.List;
import java.util.concurrent.TimeUnit;
import org.springframework.stereotype.Component;

/**
 * 执行视频模块外部进程，并限制日志输出保留量与运行时间。
 *
 * @author OmniNest
 */
@Component
public class VideoProcessExecutor {
    static final int OUTPUT_LIMIT_BYTES = 1024 * 1024;
    private static final long OUTPUT_JOIN_TIMEOUT_MILLIS = 5000;
    private static final long TERMINATION_GRACE_MILLIS = 2000;

    private final ProcessStarter processStarter;

    /**
     * 创建使用系统进程构建器的执行器。
     */
    public VideoProcessExecutor() {
        this(command -> new ProcessBuilder(command)
                .redirectErrorStream(true)
                .start());
    }

    VideoProcessExecutor(ProcessStarter processStarter) {
        this.processStarter = processStarter;
    }

    /**
     * 执行命令并持续排空合并后的标准输出与错误输出。
     *
     * @param command 外部命令及参数
     * @param timeout 最大运行时间
     * @return 退出状态和有界输出
     * @throws IOException          进程启动或输出读取失败
     * @throws InterruptedException 当前线程被中断
     */
    public Result execute(List<String> command, Duration timeout) throws IOException, InterruptedException {
        if (command == null || command.isEmpty()) {
            throw new IllegalArgumentException("外部进程命令不能为空");
        }
        if (timeout == null || timeout.isZero() || timeout.isNegative()) {
            throw new IllegalArgumentException("外部进程超时时间必须大于零");
        }

        Process process = processStarter.start(List.copyOf(command));
        // 执行器只读输出，从不写输入：立刻关闭父进程侧管道，
        // 避免长时间转码任务累积空闲文件描述符。
        process.getOutputStream().close();
        BoundedOutputCollector collector = new BoundedOutputCollector(process.getInputStream());
        Thread outputThread = Thread.ofVirtual()
                .name("video-process-output")
                .start(collector);

        boolean finished;
        try {
            finished = process.waitFor(Math.max(1L, timeout.toMillis()), TimeUnit.MILLISECONDS);
        } catch (InterruptedException e) {
            process.destroyForcibly();
            outputThread.interrupt();
            Thread.currentThread().interrupt();
            throw e;
        }

        if (!finished) {
            terminate(process);
        }
        awaitOutput(outputThread, process);
        if (finished) {
            collector.throwIfFailed();
        }

        if (!finished) {
            return new Result(-1, collector.output(), true, collector.truncated());
        }
        return new Result(process.exitValue(), collector.output(), false, collector.truncated());
    }

    private void terminate(Process process) throws InterruptedException {
        process.destroy();
        if (process.waitFor(TERMINATION_GRACE_MILLIS, TimeUnit.MILLISECONDS)) {
            return;
        }
        process.destroyForcibly();
        process.waitFor(TERMINATION_GRACE_MILLIS, TimeUnit.MILLISECONDS);
    }

    private void awaitOutput(Thread outputThread, Process process) throws InterruptedException, IOException {
        outputThread.join(OUTPUT_JOIN_TIMEOUT_MILLIS);
        if (!outputThread.isAlive()) {
            return;
        }
        process.getInputStream().close();
        outputThread.join(OUTPUT_JOIN_TIMEOUT_MILLIS);
        if (outputThread.isAlive()) {
            outputThread.interrupt();
            throw new IOException("外部进程输出流未能及时关闭");
        }
    }

    /**
     * 外部进程执行结果。
     *
     * @param exitCode        进程退出码，超时时为 -1
     * @param output          保留的合并输出
     * @param timedOut        是否因超时终止
     * @param outputTruncated 输出是否超过保留上限
     * @author OmniNest
     */
    public record Result(int exitCode, String output, boolean timedOut, boolean outputTruncated) {
        /**
         * 判断进程是否在期限内正常退出。
         *
         * @return 正常退出时返回 true
         */
        public boolean succeeded() {
            return !timedOut && exitCode == 0;
        }
    }

    /**
     * 创建外部进程，便于隔离系统进程 API 的测试边界。
     *
     * @author OmniNest
     */
    @FunctionalInterface
    interface ProcessStarter {
        /**
         * 根据命令创建系统进程。
         *
         * @param command 外部命令及参数
         * @return 已启动的系统进程
         * @throws IOException 进程启动失败
         */
        Process start(List<String> command) throws IOException;
    }

    /**
     * 持续排空进程输出，仅保留固定容量内容。
     *
     * @author OmniNest
     */
    private static final class BoundedOutputCollector implements Runnable {
        private final InputStream inputStream;
        private final ByteArrayOutputStream output = new ByteArrayOutputStream();
        private volatile IOException failure;
        private volatile boolean truncated;

        private BoundedOutputCollector(InputStream inputStream) {
            this.inputStream = inputStream;
        }

        @Override
        public void run() {
            byte[] buffer = new byte[8192];
            try (InputStream input = inputStream) {
                int read;
                while ((read = input.read(buffer)) != -1) {
                    append(buffer, read);
                }
            } catch (IOException e) {
                failure = e;
            }
        }

        private synchronized void append(byte[] buffer, int read) {
            int remaining = OUTPUT_LIMIT_BYTES - output.size();
            if (remaining > 0) {
                output.write(buffer, 0, Math.min(remaining, read));
            }
            if (read > remaining) {
                truncated = true;
            }
        }

        private synchronized String output() {
            return output.toString(StandardCharsets.UTF_8);
        }

        private boolean truncated() {
            return truncated;
        }

        private void throwIfFailed() throws IOException {
            if (failure != null) {
                throw failure;
            }
        }
    }
}
