package com.omninest.modules.file.service;

import com.omninest.common.processing.TempStagingPort;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;

/**
 * 测试用临时目录端口：直接落在系统临时目录，不做分段隔离。
 *
 * @author OmniNest
 */
final class TestTempStagingPort implements TempStagingPort {

    @Override
    public Path createTempFile(String segment, String prefix, String suffix) {
        try {
            return Files.createTempFile(prefix, suffix);
        } catch (IOException exception) {
            throw new UncheckedIOException(exception);
        }
    }

    @Override
    public Path ensureDirectory(String segment) {
        try {
            return Files.createTempDirectory(segment);
        } catch (IOException exception) {
            throw new UncheckedIOException(exception);
        }
    }

    @Override
    public void deleteQuietly(Path path) {
        if (path == null) {
            return;
        }
        try {
            Files.deleteIfExists(path);
        } catch (IOException ignored) {
            // 测试清理失败不影响断言。
        }
    }
}
