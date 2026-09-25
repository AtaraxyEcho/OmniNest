package com.omninest.common.processing;

import com.omninest.common.config.ProcessingTempProperties;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 基于 {@link ProcessingTempProperties} 的本地临时暂存实现。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ProcessingTempStagingService implements TempStagingPort {

    private final ProcessingTempProperties processingTempProperties;

    @Override
    public Path createTempFile(String segment, String prefix, String suffix) {
        Path directory = ensureDirectory(segment);
        try {
            return Files.createTempFile(directory, prefix, suffix);
        } catch (IOException exception) {
            throw new UncheckedIOException("创建处理临时文件失败: " + directory, exception);
        }
    }

    @Override
    public Path ensureDirectory(String segment) {
        return processingTempProperties.ensureSubdirectory(segment);
    }

    @Override
    public void deleteQuietly(Path path) {
        if (path == null) {
            return;
        }
        try {
            Files.deleteIfExists(path);
        } catch (IOException exception) {
            log.warn("删除处理临时路径失败: path={}, errorType={}", path, exception.getClass().getSimpleName());
        }
    }
}
