package com.omninest.app.migration;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.modules.configcenter.domain.ConfigDefinition;
import com.omninest.modules.configcenter.domain.ConfigDefinitionCatalog;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;
import org.junit.jupiter.api.Test;

/**
 * 无需 Docker 即可验证 V002 与配置中心代码目录没有漂移。
 */
class BuiltinConfigCatalogScriptContractTest {
    private static final Pattern CONFIG_ROW = Pattern.compile("\\('([^']+)',");

    @Test
    void baselineCatalogKeysMatchCodeCatalogExactly() throws IOException {
        String migration = readResource("db/migration/V002__builtin_catalog.sql");
        int start = migration.indexOf("-- 配置中心受控目录");
        int end = migration.indexOf("-- 内置角色。", start);
        assertThat(start).isGreaterThanOrEqualTo(0);
        assertThat(end).isGreaterThan(start);

        Set<String> baselineKeys = new LinkedHashSet<>();
        Matcher matcher = CONFIG_ROW.matcher(migration.substring(start, end));
        while (matcher.find()) {
            baselineKeys.add(matcher.group(1));
        }
        Set<String> catalogKeys = ConfigDefinitionCatalog.definitions().stream()
                .map(ConfigDefinition::key)
                .collect(Collectors.toCollection(LinkedHashSet::new));

        assertThat(baselineKeys).hasSize(59).containsExactlyInAnyOrderElementsOf(catalogKeys);
    }

    private String readResource(String resourceName) throws IOException {
        try (InputStream stream = getClass().getClassLoader().getResourceAsStream(resourceName)) {
            assertThat(stream).as("迁移资源 %s", resourceName).isNotNull();
            return new String(stream.readAllBytes(), StandardCharsets.UTF_8);
        }
    }
}
