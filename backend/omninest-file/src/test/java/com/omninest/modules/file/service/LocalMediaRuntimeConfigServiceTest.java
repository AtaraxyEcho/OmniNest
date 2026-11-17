package com.omninest.modules.file.service;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.config.RuntimeConfigCache;
import com.omninest.modules.file.config.LocalMediaStorageProperties;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

/**
 * 本地媒体运行时配置服务测试。
 *
 * @author OmniNest
 */
class LocalMediaRuntimeConfigServiceTest {
    private final ConfigValueProvider valueProvider = Mockito.mock(ConfigValueProvider.class);
    private final RuntimeConfigCache cache = Mockito.mock(RuntimeConfigCache.class);
    private final LocalMediaStorageProperties deploymentProperties = new LocalMediaStorageProperties();
    private final Map<String, String> values = new HashMap<>();
    private LocalMediaRuntimeConfigService configService;

    @BeforeEach
    void setUp() {
        values.clear();
        deploymentProperties.setEnabled(true);
        deploymentProperties.setMaxFilesPerScan(1000);
        deploymentProperties.setMaxScanDepth(16);
        Mockito.when(cache.get(Mockito.anyString())).thenReturn(Optional.empty());
        Mockito.when(valueProvider.findByKey(Mockito.anyString()))
                .thenAnswer(invocation -> Optional.ofNullable(values.get(invocation.getArgument(0))));
        configService = new LocalMediaRuntimeConfigService(
                valueProvider,
                cache,
                deploymentProperties
        );
    }

    @Test
    void deploymentGateCannotBeEnabledByRuntimeConfiguration() {
        deploymentProperties.setEnabled(false);
        values.put(LocalMediaRuntimeConfigService.ENABLED, "true");

        assertThat(configService.isEnabled()).isFalse();
    }

    @Test
    void runtimeConfigurationCannotChangeDeploymentBoundary() {
        values.put(LocalMediaRuntimeConfigService.ENABLED, "false");

        assertThat(configService.isEnabled()).isTrue();
    }

    @Test
    void legacyScanLimitsCannotOverrideApplicationDefaults() {
        values.put(LocalMediaRuntimeConfigService.MAX_FILES_PER_SCAN, "5000");
        values.put(LocalMediaRuntimeConfigService.MAX_SCAN_DEPTH, "64");

        assertThat(configService.maxFilesPerScan()).isEqualTo(1000);
        assertThat(configService.maxScanDepth()).isEqualTo(16);
    }

    @Test
    void invalidApplicationLimitsAreClampedToOne() {
        deploymentProperties.setMaxFilesPerScan(0);
        deploymentProperties.setMaxScanDepth(-10);

        assertThat(configService.maxFilesPerScan()).isEqualTo(1);
        assertThat(configService.maxScanDepth()).isEqualTo(1);
    }
}
