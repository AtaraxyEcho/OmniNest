package com.omninest.modules.backdrop.config;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.config.RuntimeConfigCache;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class BackdropRuntimeConfigServiceTest {

    private ConfigValueProvider configValueProvider;
    private BackdropRuntimeConfigService configService;

    @BeforeEach
    void setUp() {
        configValueProvider = mock(ConfigValueProvider.class);
        RuntimeConfigCache runtimeConfigCache = mock(RuntimeConfigCache.class);
        when(runtimeConfigCache.get(anyString())).thenReturn(Optional.empty());
        configService = new BackdropRuntimeConfigService(configValueProvider, runtimeConfigCache);
    }

    @Test
    void returnsPlanDefaultsWhenCatalogEmpty() {
        assertThat(configService.maxImageBytes()).isEqualTo(20L * 1024 * 1024);
        assertThat(configService.maxVideoBytes()).isEqualTo(448L * 1024 * 1024);
        assertThat(configService.maxAssetsPerUser()).isEqualTo(30);
        assertThat(configService.uploadRatePerHour()).isEqualTo(20);
    }

    @Test
    void readsConfiguredLimits() {
        when(configValueProvider.findByKey(BackdropRuntimeConfigService.MAX_IMAGE_BYTES))
                .thenReturn(Optional.of("1048576"));
        when(configValueProvider.findByKey(BackdropRuntimeConfigService.MAX_ASSETS_PER_USER))
                .thenReturn(Optional.of("50"));

        assertThat(configService.maxImageBytes()).isEqualTo(1024 * 1024);
        assertThat(configService.maxAssetsPerUser()).isEqualTo(50);
    }

    @Test
    void readsAssetBytesWithoutHardcodedCeiling() {
        when(configValueProvider.findByKey(BackdropRuntimeConfigService.MAX_VIDEO_BYTES))
                .thenReturn(Optional.of("469762048"));
        when(configValueProvider.findByKey(BackdropRuntimeConfigService.MAX_IMAGE_BYTES))
                .thenReturn(Optional.of("1024"));

        assertThat(configService.maxVideoBytes()).isEqualTo(448L * 1024 * 1024);
        assertThat(configService.maxImageBytes()).isEqualTo(1024);
    }

    @Test
    void readsVideoLimitAboveIntRangeWithoutFallingBack() {
        when(configValueProvider.findByKey(BackdropRuntimeConfigService.MAX_VIDEO_BYTES))
                .thenReturn(Optional.of("2147483648"));

        assertThat(configService.maxVideoBytes()).isEqualTo(2_147_483_648L);
    }

    @Test
    void clampsCountAndRateLimits() {
        when(configValueProvider.findByKey(BackdropRuntimeConfigService.MAX_ASSETS_PER_USER))
                .thenReturn(Optional.of("999"));
        when(configValueProvider.findByKey(BackdropRuntimeConfigService.UPLOAD_RATE_PER_HOUR))
                .thenReturn(Optional.of("0"));

        assertThat(configService.maxAssetsPerUser()).isEqualTo(200);
        assertThat(configService.uploadRatePerHour()).isEqualTo(1);
    }

    @Test
    void fallsBackToDefaultsOnUnparsableValue() {
        when(configValueProvider.findByKey(BackdropRuntimeConfigService.MAX_VIDEO_BYTES))
                .thenReturn(Optional.of("not-a-number"));

        assertThat(configService.maxVideoBytes()).isEqualTo(448L * 1024 * 1024);
    }
}
