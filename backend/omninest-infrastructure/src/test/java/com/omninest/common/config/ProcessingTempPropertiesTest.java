package com.omninest.common.config;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;

/**
 * 处理目录根配置测试。
 *
 * @author OmniNest
 */
class ProcessingTempPropertiesTest {

    @Test
    void createsSubdirectoryUnderConfiguredRoot() throws Exception {
        Path tempRoot = Files.createTempDirectory("omninest-processing-test");
        ProcessingTempProperties properties = new ProcessingTempProperties();
        properties.setRoot(tempRoot.toString());

        Path resolved = properties.ensureSubdirectory("music-cover");

        assertThat(resolved).startsWith(tempRoot.toAbsolutePath().normalize());
        assertThat(Files.isDirectory(resolved)).isTrue();
    }

    @Test
    void rejectsSegmentEscapingRoot() {
        ProcessingTempProperties properties = new ProcessingTempProperties();
        properties.setRoot(System.getProperty("java.io.tmpdir"));

        assertThatThrownBy(() -> properties.ensureSubdirectory("../escape"))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
