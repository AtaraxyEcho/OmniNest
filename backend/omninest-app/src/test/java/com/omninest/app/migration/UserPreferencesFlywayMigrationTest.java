package com.omninest.app.migration;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.OffsetDateTime;
import java.util.UUID;
import org.assertj.core.api.Assertions;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.springframework.test.annotation.DirtiesContext;

/**
 * 在真实 PostgreSQL 中验证用户偏好审计字段迁移。
 *
 * @author Notask Flow Team
 */
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@Testcontainers(disabledWithoutDocker = true)
class UserPreferencesFlywayMigrationTest {
    private static final String IMAGE = "postgres:18-alpine";

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_migration")
            .withUsername("omninest")
            .withPassword("omninest");

    @Test
    void baselineRequiresAuditFields() throws SQLException {
        Flyway current = flyway();
        current.migrate();
        UUID preferenceId = insertPreference();

        assertAuditFieldsGenerated(preferenceId);
        assertCreatedAtIsRequired();
        Assertions.assertThat(current.info().current().getVersion().getVersion()).isEqualTo("002");
    }

    private Flyway flyway() {
        return Flyway.configure()
                .dataSource(POSTGRES.getJdbcUrl(), POSTGRES.getUsername(), POSTGRES.getPassword())
                .locations("classpath:db/migration")
                .validateMigrationNaming(true)
                .schemas("omni")
                .defaultSchema("omni")
                .cleanDisabled(true)
                .load();
    }

    private UUID insertPreference() throws SQLException {
        UUID id = UUID.randomUUID();
        String sql = """
                INSERT INTO omni.user_preferences
                    (id, owner_user_id, scope, preferences, created_at, updated_at, version)
                VALUES (?, ?, ?, '{}'::jsonb, NOW(), NOW(), 0)
                """;
        try (Connection connection = POSTGRES.createConnection("");
             PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setObject(1, id);
            statement.setObject(2, UUID.randomUUID());
            statement.setString(3, "appearance.v1");
            statement.executeUpdate();
        }
        return id;
    }

    private void assertAuditFieldsGenerated(UUID preferenceId) throws SQLException {
        String sql = "SELECT created_at, updated_at FROM omni.user_preferences WHERE id = ?";
        try (Connection connection = POSTGRES.createConnection("");
             PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setObject(1, preferenceId);
            try (ResultSet result = statement.executeQuery()) {
                Assertions.assertThat(result.next()).isTrue();
                Assertions.assertThat(result.getObject("created_at", OffsetDateTime.class))
                        .isNotNull();
                Assertions.assertThat(result.getObject("updated_at", OffsetDateTime.class))
                        .isNotNull();
            }
        }
    }

    private void assertCreatedAtIsRequired() throws SQLException {
        String sql = """
                SELECT is_nullable
                FROM information_schema.columns
                WHERE table_schema = 'omni'
                  AND table_name = 'user_preferences'
                  AND column_name = 'created_at'
                """;
        try (Connection connection = POSTGRES.createConnection("");
             Statement statement = connection.createStatement();
             ResultSet result = statement.executeQuery(sql)) {
            Assertions.assertThat(result.next()).isTrue();
            Assertions.assertThat(result.getString("is_nullable")).isEqualTo("NO");
        }
    }
}
