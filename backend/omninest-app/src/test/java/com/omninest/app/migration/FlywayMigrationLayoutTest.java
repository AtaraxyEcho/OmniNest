package com.omninest.app.migration;

import java.net.URL;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;

/**
 * Flyway 迁移资源目录约束测试。
 *
 * @author OmniNest
 */
class FlywayMigrationLayoutTest {
    private static final Pattern MIGRATION_NAME = Pattern.compile("V\\d{3}__[a-z0-9_]+\\.sql");

    @Test
    void migrationDirectoryContainsOnlyVersionedScripts() throws Exception {
        URL resource = Thread.currentThread()
                .getContextClassLoader()
                .getResource("db/migration");
        Assertions.assertThat(resource).as("Flyway 迁移目录必须存在").isNotNull();

        List<String> scriptNames;
        try (Stream<Path> files = Files.list(Path.of(resource.toURI()))) {
            scriptNames = files
                    .filter(Files::isRegularFile)
                    .map(path -> path.getFileName().toString())
                    .filter(name -> name.endsWith(".sql"))
                    .sorted()
                    .toList();
        }

        Assertions.assertThat(scriptNames).isNotEmpty();
        Assertions.assertThat(scriptNames).containsExactly(
                "V001__init_schema.sql",
                "V002__builtin_catalog.sql"
        );
        Assertions.assertThat(scriptNames)
                .allMatch(name -> MIGRATION_NAME.matcher(name).matches());
    }

    @Test
    void baselineDoesNotContainRuntimeDataForeignKeysOrKnownSecrets() throws Exception {
        URL resource = Thread.currentThread()
                .getContextClassLoader()
                .getResource("db/migration/V001__init_schema.sql");
        Assertions.assertThat(resource).isNotNull();

        String sql = Files.readString(Path.of(resource.toURI()), StandardCharsets.UTF_8);

        Assertions.assertThat(sql)
                .doesNotContain("INSERT INTO")
                .doesNotContain("flyway_schema_history")
                .doesNotContain("FOREIGN KEY")
                .doesNotContain("REFERENCES")
                .doesNotContain("ON DELETE")
                .doesNotContain("ON UPDATE")
                .doesNotContain("BEGIN PRIVATE KEY")
                .doesNotContain("AIza");
    }
}
