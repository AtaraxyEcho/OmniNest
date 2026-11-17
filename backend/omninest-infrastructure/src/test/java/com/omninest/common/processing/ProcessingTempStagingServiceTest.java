package com.omninest.common.processing;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.omninest.common.config.ProcessingTempProperties;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * 处理临时暂存端口测试。
 *
 * @author OmniNest
 */
class ProcessingTempStagingServiceTest {

    @TempDir
    Path tempDir;

    @Test
    void createTempFileUsesConfiguredProcessingRoot() throws Exception {
        ProcessingTempProperties properties = new ProcessingTempProperties();
        properties.setRoot(tempDir.resolve("processing").toString());
        ProcessingTempStagingService service = new ProcessingTempStagingService(properties);

        Path file = service.createTempFile("music-cover", "cover-", ".jpg");

        assertThat(file).startsWith(tempDir.resolve("processing").resolve("music-cover"));
        assertThat(Files.isRegularFile(file)).isTrue();
        service.deleteQuietly(file);
        assertThat(Files.exists(file)).isFalse();
    }

    @Test
    void ensureDirectoryRejectsEscapeSegment() {
        ProcessingTempProperties properties = new ProcessingTempProperties();
        properties.setRoot(tempDir.resolve("processing").toString());
        ProcessingTempStagingService service = new ProcessingTempStagingService(properties);

        assertThatThrownBy(() -> service.ensureDirectory("../escape"))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
