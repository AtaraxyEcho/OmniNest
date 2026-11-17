package com.omninest.common.config;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.common.storage.LocalExternalStorageSettings;
import org.junit.jupiter.api.Test;

/**
 * Rclone 配置与本地外部存储设置契约映射测试。
 *
 * @author OmniNest
 */
class RclonePropertiesTest {

    @Test
    void localHostPathIsExposedThroughSettingsContract() {
        RcloneProperties properties = new RcloneProperties();
        properties.setLocalHostPath("D:/storage/local");
        properties.setImportHostPath("D:/storage/imports");
        properties.setImportContainerPath("/mnt/imports");

        LocalExternalStorageSettings settings = properties;

        assertThat(settings.localHostRoot()).isEqualTo("D:/storage/local");
        assertThat(settings.importHostRoot()).isEqualTo("D:/storage/imports");
        assertThat(settings.importContainerRoot()).isEqualTo("/mnt/imports");
    }
}
