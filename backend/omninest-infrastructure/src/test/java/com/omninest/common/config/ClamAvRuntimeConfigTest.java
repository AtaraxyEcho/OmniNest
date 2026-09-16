package com.omninest.common.config;

import static org.assertj.core.api.Assertions.assertThat;
import java.time.Duration;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.mock.env.MockEnvironment;

/**
 * 验证 ClamAV 运行时配置的默认值、热更新读取和边界限制。
 *
 * @author OmniNest
 */
class ClamAvRuntimeConfigTest {

    @Test
    void readsSupportedLegacyOverridesButKeepsInternalPortAndTimeoutDefaults() {
        ConfigValueProvider provider = Mockito.mock(ConfigValueProvider.class);
        RuntimeConfigCache cache = Mockito.mock(RuntimeConfigCache.class);
        ClamAvProperties properties = new ClamAvProperties();
        Mockito.when(cache.get("security.clamav.enabled")).thenReturn(Optional.of("false"));
        Mockito.when(cache.get("security.clamav.host")).thenReturn(Optional.of("clamav.internal"));
        Mockito.when(cache.get("security.clamav.port")).thenReturn(Optional.of("70000"));
        Mockito.when(cache.get("security.clamav.timeout-millis")).thenReturn(Optional.of("100"));
        LegacyDeploymentConfigResolver resolver = new LegacyDeploymentConfigResolver(
                provider,
                cache,
                new MockEnvironment()
        );
        ClamAvRuntimeConfig config = new ClamAvRuntimeConfig(properties, resolver);

        assertThat(config.isEnabled()).isFalse();
        assertThat(config.host()).isEqualTo("clamav.internal");
        assertThat(config.port()).isEqualTo(3310);
        assertThat(config.timeout()).isEqualTo(Duration.ofSeconds(10));
    }

    @Test
    void readsHotTimeoutValueFromConfigCenter() {
        ConfigValueProvider provider = Mockito.mock(ConfigValueProvider.class);
        RuntimeConfigCache cache = Mockito.mock(RuntimeConfigCache.class);
        ClamAvProperties properties = new ClamAvProperties();
        Mockito.when(cache.get("clamav.timeout-millis")).thenReturn(Optional.of("60000"));
        LegacyDeploymentConfigResolver resolver = new LegacyDeploymentConfigResolver(
                provider,
                cache,
                new MockEnvironment()
        );
        ClamAvRuntimeConfig config = new ClamAvRuntimeConfig(properties, resolver, provider, cache);

        assertThat(config.timeout()).isEqualTo(Duration.ofSeconds(60));
    }

    @Test
    void rejectsOutOfRangeHotTimeoutAndFallsBackToDeploymentDefault() {
        ConfigValueProvider provider = Mockito.mock(ConfigValueProvider.class);
        RuntimeConfigCache cache = Mockito.mock(RuntimeConfigCache.class);
        ClamAvProperties properties = new ClamAvProperties();
        Mockito.when(cache.get("clamav.timeout-millis")).thenReturn(Optional.of("100"));
        LegacyDeploymentConfigResolver resolver = new LegacyDeploymentConfigResolver(
                provider,
                cache,
                new MockEnvironment()
        );
        ClamAvRuntimeConfig config = new ClamAvRuntimeConfig(properties, resolver, provider, cache);

        assertThat(config.timeout()).isEqualTo(Duration.ofSeconds(10));
    }

    @Test
    void fallsBackToLegacyKeyWhenHotKeyMissing() {
        ConfigValueProvider provider = Mockito.mock(ConfigValueProvider.class);
        RuntimeConfigCache cache = Mockito.mock(RuntimeConfigCache.class);
        ClamAvProperties properties = new ClamAvProperties();
        Mockito.when(cache.get("clamav.timeout-millis")).thenReturn(Optional.empty());
        Mockito.when(cache.get("security.clamav.timeout-millis")).thenReturn(Optional.of("30000"));
        LegacyDeploymentConfigResolver resolver = new LegacyDeploymentConfigResolver(
                provider,
                cache,
                new MockEnvironment()
        );
        ClamAvRuntimeConfig config = new ClamAvRuntimeConfig(properties, resolver, provider, cache);

        assertThat(config.timeout()).isEqualTo(Duration.ofSeconds(30));
    }
}
