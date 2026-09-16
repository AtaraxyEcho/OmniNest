package com.omninest.modules.configcenter.domain;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

class ConfigDefinitionCatalogTest {
    @Test
    void catalogContainsOnlyTheApprovedRuntimeSettings() {
        var definitions = ConfigDefinitionCatalog.definitions();

        assertThat(definitions).hasSize(68);
        assertThat(definitions).extracting(ConfigDefinition::key).doesNotHaveDuplicates();
        assertThat(definitions)
                .filteredOn(definition -> definition.surface() == ConfigSurface.GENERAL)
                .hasSize(29);
        assertThat(definitions)
                .filteredOn(definition -> definition.surface() == ConfigSurface.INTEGRATION)
                .hasSize(39);
    }

    @Test
    void backdropDefinitionsExposeQuotaAndUploadLimits() {
        assertThat(ConfigDefinitionCatalog.find("backdrop.max-image-bytes"))
                .hasValueSatisfying(definition -> assertThat(definition.defaultValue()).isEqualTo("20971520"));
        assertThat(ConfigDefinitionCatalog.find("backdrop.max-video-bytes"))
                .hasValueSatisfying(definition -> assertThat(definition.defaultValue()).isEqualTo("67108864"));
        assertThat(ConfigDefinitionCatalog.find("backdrop.max-assets-per-user"))
                .hasValueSatisfying(definition -> assertThat(definition.defaultValue()).isEqualTo("30"));
        assertThat(ConfigDefinitionCatalog.find("backdrop.upload.rate-per-hour"))
                .hasValueSatisfying(definition -> assertThat(definition.defaultValue()).isEqualTo("20"));
    }

    @Test
    void catalogTracksDeprecatedKeysWithoutMakingThemEditable() {
        assertThat(ConfigDefinitionCatalog.isKnownHidden("rate-limit.default-limit")).isTrue();
        assertThat(ConfigDefinitionCatalog.isKnownHidden("transcode.enabled")).isTrue();
        assertThat(ConfigDefinitionCatalog.find("transcode.enabled")).isEmpty();
        assertThat(ConfigDefinitionCatalog.find("rate-limit.default-limit")).isEmpty();
        assertThat(ConfigDefinitionCatalog.find("media.tmdb.url")).isPresent();
        assertThat(ConfigDefinitionCatalog.find("weather.qweather.url")).isPresent();
        assertThat(ConfigDefinitionCatalog.find("weather.location")).isPresent();
        assertThat(ConfigDefinitionCatalog.find("music.netease.url")).isPresent();
        assertThat(ConfigDefinitionCatalog.find("music.qq.u-url")).isPresent();
        assertThat(ConfigDefinitionCatalog.find("music.qq.c-url")).isPresent();
    }

    @Test
    void numericDefinitionsAcceptOnlyIntegralValues() {
        ConfigDefinition definition = ConfigDefinitionCatalog.find("storage.quota.default").orElseThrow();

        assertThat(definition.normalize("10.0")).isEqualTo("10");
        assertThatThrownBy(() -> definition.normalize("10.5"))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("整数");
    }

    @Test
    void restrictedMediaDefinitionsAreMarkedForSuperAdminOnly() {
        assertThat(ConfigDefinitionCatalog.find("media.import.enabled").orElseThrow().superAdminOnly()).isTrue();
        assertThat(ConfigDefinitionCatalog.find("media.tmdb.key")
                .orElseThrow()
                .superAdminOnly()).isTrue();
        assertThat(ConfigDefinitionCatalog.find("reader.gbooks.key")
                .orElseThrow()
                .superAdminOnly()).isTrue();
    }

    @Test
    void tmdbStrategyRetainsSupportedRawQueryMode() {
        ConfigDefinition definition = ConfigDefinitionCatalog.find("media.tmdb.strategy").orElseThrow();

        assertThat(definition.normalize("RAW_ONLY")).isEqualTo("RAW_ONLY");
    }

    @Test
    void endpointDefinitionsAcceptSafeHttpSyntaxOnly() {
        ConfigDefinition definition = ConfigDefinitionCatalog.find("media.tmdb.url").orElseThrow();

        assertThat(definition.normalize(" https://tmdb.example/v3 "))
                .isEqualTo("https://tmdb.example/v3");
        assertThatThrownBy(() -> definition.normalize("file:///tmp/tmdb"))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> definition.normalize("https://user:password@tmdb.example/v3"))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> definition.normalize("https://tmdb.example/v3?token=secret"))
                .isInstanceOf(IllegalArgumentException.class);
    }
}
