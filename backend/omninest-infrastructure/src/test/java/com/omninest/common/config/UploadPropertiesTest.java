package com.omninest.common.config;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.common.upload.FileUploadSettings;
import java.time.Duration;
import org.junit.jupiter.api.Test;

/**
 * 上传配置与文件上传设置契约映射测试。
 *
 * @author OmniNest
 */
class UploadPropertiesTest {

    @Test
    void defaultValuesAreExposedThroughSettingsContract() {
        FileUploadSettings settings = new UploadProperties();

        assertThat(settings.presignedUrlTtl()).isEqualTo(Duration.ofHours(4));
        assertThat(settings.sessionTtl()).isEqualTo(Duration.ofHours(24));
        assertThat(settings.bandwidthLimitEnabled()).isTrue();
        assertThat(settings.maxPresignedPartsPerSecond()).isEqualTo(4);
        assertThat(settings.presignedPartBurstCapacity()).isEqualTo(8);
    }

    @Test
    void configuredValuesAreExposedThroughSettingsContract() {
        UploadProperties properties = new UploadProperties();
        properties.setUrlTtl(Duration.ofMinutes(30));
        properties.setSessionTtl(Duration.ofHours(2));
        properties.getBandwidth().setEnabled(false);
        properties.getBandwidth().setMaxPartsPerSecond(12);
        properties.getBandwidth().setBurstCapacity(20);

        FileUploadSettings settings = properties;

        assertThat(settings.presignedUrlTtl()).isEqualTo(Duration.ofMinutes(30));
        assertThat(settings.sessionTtl()).isEqualTo(Duration.ofHours(2));
        assertThat(settings.bandwidthLimitEnabled()).isFalse();
        assertThat(settings.maxPresignedPartsPerSecond()).isEqualTo(12);
        assertThat(settings.presignedPartBurstCapacity()).isEqualTo(20);
    }
}
