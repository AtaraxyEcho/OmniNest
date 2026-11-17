package com.omninest.modules.video.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.time.Duration;
import java.util.Arrays;
import java.util.List;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Test;

/**
 * 视频外部进程执行器测试。
 *
 * @author OmniNest
 */
class VideoProcessExecutorTest {

    @Test
    void shouldBoundRetainedOutputWhileDrainingProcessStream() throws Exception {
        byte[] output = new byte[VideoProcessExecutor.OUTPUT_LIMIT_BYTES + 4096];
        Arrays.fill(output, (byte) 'a');
        FakeProcess process = new FakeProcess(output, true, 0);
        VideoProcessExecutor executor = new VideoProcessExecutor(command -> process);

        VideoProcessExecutor.Result result = executor.execute(List.of("fake"), Duration.ofSeconds(1));

        assertTrue(result.succeeded());
        assertTrue(result.outputTruncated());
        assertEquals(VideoProcessExecutor.OUTPUT_LIMIT_BYTES, result.output().length());
    }

    @Test
    void shouldTerminateProcessWhenTimeoutExpires() throws Exception {
        FakeProcess process = new FakeProcess(new byte[0], false, 0);
        VideoProcessExecutor executor = new VideoProcessExecutor(command -> process);

        VideoProcessExecutor.Result result = executor.execute(List.of("fake"), Duration.ofMillis(1));

        assertTrue(result.timedOut());
        assertEquals(-1, result.exitCode());
        assertFalse(process.isAlive());
    }

    /**
     * 提供可控完成状态与输出内容的测试进程。
     *
     * @author OmniNest
     */
    private static final class FakeProcess extends Process {
        private final InputStream inputStream;
        private final boolean completesNormally;
        private final int exitCode;
        private boolean alive = true;

        private FakeProcess(byte[] output, boolean completesNormally, int exitCode) {
            this.inputStream = new ByteArrayInputStream(output);
            this.completesNormally = completesNormally;
            this.exitCode = exitCode;
        }

        @Override
        public OutputStream getOutputStream() {
            return OutputStream.nullOutputStream();
        }

        @Override
        public InputStream getInputStream() {
            return inputStream;
        }

        @Override
        public InputStream getErrorStream() {
            return InputStream.nullInputStream();
        }

        @Override
        public int waitFor() {
            alive = false;
            return exitCode;
        }

        @Override
        public boolean waitFor(long timeout, TimeUnit unit) {
            if (completesNormally || !alive) {
                alive = false;
                return true;
            }
            return false;
        }

        @Override
        public int exitValue() {
            return exitCode;
        }

        @Override
        public void destroy() {
            alive = false;
        }

        @Override
        public Process destroyForcibly() {
            alive = false;
            return this;
        }

        @Override
        public boolean isAlive() {
            return alive;
        }
    }
}
