package com.omninest.modules.video.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.config.RuntimeConfigCache;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

class MediaRuntimeConfigServiceTest {

    private ConfigValueProvider configValueProvider;
    private MediaRuntimeConfigService configService;

    @BeforeEach
    void setUp() {
        configValueProvider = mock(ConfigValueProvider.class);
        RuntimeConfigCache runtimeConfigCache = mock(RuntimeConfigCache.class);
        when(runtimeConfigCache.get(anyString())).thenReturn(Optional.empty());
        configService = new MediaRuntimeConfigService(configValueProvider, runtimeConfigCache);
    }

    @Test
    void readsEditableProviderSettingsFromRuntimeCatalog() {
        when(configValueProvider.findByKey(MediaRuntimeConfigService.TMDB_BASE_URL))
                .thenReturn(Optional.of("https://tmdb.example/v3"));

        assertThat(configService.tmdbBaseUrl()).isEqualTo("https://tmdb.example/v3");
    }

    @Test
    void clampsEditableSearchTuning() {
        when(configValueProvider.findByKey(MediaRuntimeConfigService.TMDB_MAX_RESULTS))
                .thenReturn(Optional.of("100"));
        when(configValueProvider.findByKey(MediaRuntimeConfigService.TMDB_SEARCH_STRATEGY))
                .thenReturn(Optional.of("CUSTOM"));

        assertThat(configService.tmdbMaxResults()).isEqualTo(20);
        assertThat(configService.tmdbSearchQueriesStrategy()).isEqualTo("NORMALIZED_AND_FALLBACKS");
    }

    @Test
    void readsCanonicalCredentialsAndLegacyTranscodeFallback() {
        when(configValueProvider.findByKey(MediaRuntimeConfigService.TMDB_API_KEY))
                .thenReturn(Optional.of("tmdb-key"));
        when(configValueProvider.findByKey(MediaRuntimeConfigService.TMDB_ACCESS_TOKEN))
                .thenReturn(Optional.of("tmdb-token"));
        when(configValueProvider.findByKey("transcode.enabled"))
                .thenReturn(Optional.of("false"));

        assertThat(configService.tmdbApiKey()).isEqualTo("tmdb-key");
        assertThat(configService.tmdbAccessToken()).isEqualTo("tmdb-token");
        assertThat(configService.transcodeEnabled()).isFalse();
    }

    @Test
    void transcodeDefaultsToDisabled() {
        when(configValueProvider.findByKey(MediaRuntimeConfigService.TRANSCODE_ENABLED))
                .thenReturn(Optional.empty());
        when(configValueProvider.findByKey("transcode.enabled")).thenReturn(Optional.empty());

        assertThat(configService.transcodeEnabled()).isFalse();
    }
}
