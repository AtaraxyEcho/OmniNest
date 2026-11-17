package com.omninest.modules.quota.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.config.RuntimeConfigCache;
import com.omninest.modules.quota.QuotaStatus;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

/**
 * 运行时存储配额策略测试。
 *
 * @author OmniNest
 */
class RuntimeStorageQuotaPolicyTest {

    private ConfigValueProvider configValueProvider;
    private RuntimeStorageQuotaPolicy policy;

    @BeforeEach
    void setUp() {
        configValueProvider = mock(ConfigValueProvider.class);
        policy = new RuntimeStorageQuotaPolicy(
                configValueProvider,
                mock(RuntimeConfigCache.class)
        );
    }

    @Test
    void defaultQuotaBytesConvertsConfiguredGigabytes() {
        when(configValueProvider.findByKey("storage.quota.default.gb"))
                .thenReturn(Optional.of("50"));

        assertThat(policy.defaultQuotaBytes()).isEqualTo(50L * 1024 * 1024 * 1024);
    }

    @Test
    void defaultQuotaBytesUsesTenGigabytesForMissingConfig() {
        when(configValueProvider.findByKey("storage.quota.default.gb"))
                .thenReturn(Optional.empty());

        assertThat(policy.defaultQuotaBytes()).isEqualTo(10L * 1024 * 1024 * 1024);
    }

    @Test
    void defaultQuotaBytesUsesTenGigabytesForInvalidConfig() {
        when(configValueProvider.findByKey("storage.quota.default.gb"))
                .thenReturn(Optional.of("invalid"));

        assertThat(policy.defaultQuotaBytes()).isEqualTo(10L * 1024 * 1024 * 1024);
    }

    @Test
    void defaultQuotaBytesTreatsZeroAsUnlimited() {
        when(configValueProvider.findByKey("storage.quota.default.gb"))
                .thenReturn(Optional.of("0"));

        assertThat(policy.defaultQuotaBytes()).isZero();
    }

    @Test
    void resolveStatusUsesConfiguredWarningThreshold() {
        when(configValueProvider.findByKey("storage.quota.warning.percent"))
                .thenReturn(Optional.of("70"));

        assertThat(policy.resolveStatus(700, 1000, false)).isEqualTo(QuotaStatus.WARNING);
        assertThat(policy.resolveStatus(999, 1000, true)).isEqualTo(QuotaStatus.NORMAL);
    }

    @Test
    void resolveStatusClampsWarningThresholdToSupportedRange() {
        when(configValueProvider.findByKey("storage.quota.warning.percent"))
                .thenReturn(Optional.of("10"));

        assertThat(policy.resolveStatus(500, 1000, false)).isEqualTo(QuotaStatus.WARNING);
    }

    @Test
    void resolveStatusTreatsZeroQuotaAsUnlimited() {
        assertThat(policy.resolveStatus(Long.MAX_VALUE, 0, false)).isEqualTo(QuotaStatus.NORMAL);
    }
}
