package com.omninest.modules.reader.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.config.RuntimeConfigCache;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

class ReaderRuntimeConfigServiceTest {

    @Test
    void canonicalImportSwitchTakesPrecedence() {
        ConfigValueProvider provider = Mockito.mock(ConfigValueProvider.class);
        RuntimeConfigCache cache = Mockito.mock(RuntimeConfigCache.class);
        when(cache.get(Mockito.anyString())).thenReturn(Optional.empty());
        when(provider.findByKey(ReaderRuntimeConfigService.AUTO_IMPORT_ENABLED))
                .thenReturn(Optional.of("false"));

        ReaderRuntimeConfigService service = new ReaderRuntimeConfigService(provider, cache);

        assertThat(service.autoImportEnabled()).isFalse();
    }

    @Test
    void fallsBackToLegacyImportSwitch() {
        ConfigValueProvider provider = Mockito.mock(ConfigValueProvider.class);
        RuntimeConfigCache cache = Mockito.mock(RuntimeConfigCache.class);
        when(cache.get(Mockito.anyString())).thenReturn(Optional.empty());
        when(provider.findByKey("reader.auto-import.enabled"))
                .thenReturn(Optional.of("false"));

        ReaderRuntimeConfigService service = new ReaderRuntimeConfigService(provider, cache);

        assertThat(service.autoImportEnabled()).isFalse();
    }
}
