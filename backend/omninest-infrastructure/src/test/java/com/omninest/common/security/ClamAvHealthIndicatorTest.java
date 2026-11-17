package com.omninest.common.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.common.config.ClamAvRuntimeConfig;
import org.junit.jupiter.api.Test;
import org.springframework.boot.health.contributor.Status;

/**
 * ClamAV 健康检查测试。
 *
 * @author OmniNest
 */
class ClamAvHealthIndicatorTest {

    @Test
    void reportsUpWhenClamdRespondsToPing() {
        ClamAvRuntimeConfig runtimeConfig = mock(ClamAvRuntimeConfig.class);
        ClamAvScanner scanner = mock(ClamAvScanner.class);
        when(runtimeConfig.isEnabled()).thenReturn(true);
        when(runtimeConfig.host()).thenReturn("clamav");
        when(runtimeConfig.port()).thenReturn(3310);
        when(scanner.ping("clamav", 3310, 3000)).thenReturn(true);

        var health = new ClamAvHealthIndicator(scanner, runtimeConfig).health();

        assertThat(health.getStatus()).isEqualTo(Status.UP);
        assertThat(health.getDetails()).containsEntry("host", "clamav");
    }
}
