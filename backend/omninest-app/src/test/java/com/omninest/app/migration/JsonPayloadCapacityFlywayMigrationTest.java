package com.omninest.app.migration;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.UUID;
import org.assertj.core.api.Assertions;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;
import org.springframework.test.annotation.DirtiesContext;

/**
 * 在真实 PostgreSQL 中验证结构化载荷容量约束。
 *
 * @author OmniNest
 */
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_CLASS)
@Testcontainers(disabledWithoutDocker = true)
class JsonPayloadCapacityFlywayMigrationTest {
    private static final int EXPECTED_ACTIVE_CAPACITY_CONSTRAINTS = 43;
    private static final String IMAGE = "postgres:18-alpine";

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_json_capacity")
            .withUsername("omninest")
            .withPassword("omninest");

    @BeforeAll
    static void migrateSchema() {
        Flyway.configure()
                .dataSource(POSTGRES.getJdbcUrl(), POSTGRES.getUsername(), POSTGRES.getPassword())
                .locations("classpath:db/migration")
                .validateMigrationNaming(true)
                .schemas("omni")
                .defaultSchema("omni")
                .load()
                .migrate();
    }

    @Test
    void migrationAddsAndValidatesAllCapacityConstraints() throws SQLException {
        String sql = """
                SELECT count(*)
                FROM pg_constraint
                WHERE connamespace = 'omni'::regnamespace
                  AND conname LIKE 'ck_%_json_size'
                  AND convalidated
                """;
        try (Connection connection = POSTGRES.createConnection("");
             Statement statement = connection.createStatement();
             ResultSet result = statement.executeQuery(sql)) {
            Assertions.assertThat(result.next()).isTrue();
            Assertions.assertThat(result.getInt(1)).isEqualTo(EXPECTED_ACTIVE_CAPACITY_CONSTRAINTS);
        }
    }

    @Test
    void userPreferencesConstraintAcceptsNormalPayloadAndRejectsOversizedPayload() throws SQLException {
        insertPreference(1024);

        Assertions.assertThatThrownBy(() -> insertPreference(70 * 1024))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("ck_user_preferences_json_size");
    }

    @Test
    void taskPayloadConstraintRejectsOversizedJsonText() {
        Assertions.assertThatThrownBy(() -> insertTaskPayload(300 * 1024))
                .isInstanceOf(SQLException.class)
                .hasMessageContaining("ck_sys_tasks_payload_json_size");
    }

    private void insertPreference(int valueLength) throws SQLException {
        String sql = """
                INSERT INTO omni.user_preferences
                    (id, owner_user_id, scope, preferences, created_at, updated_at, version)
                VALUES (?, ?, ?, jsonb_build_object('value', repeat('x', ?)), NOW(), NOW(), 0)
                """;
        try (Connection connection = POSTGRES.createConnection("");
             PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setObject(1, UUID.randomUUID());
            statement.setObject(2, UUID.randomUUID());
            statement.setString(3, "capacity." + UUID.randomUUID().toString().substring(0, 8));
            statement.setInt(4, valueLength);
            statement.executeUpdate();
        }
    }

    private void insertTaskPayload(int valueLength) throws SQLException {
        String sql = """
                INSERT INTO omni.sys_tasks
                    (id, task_type, status, payload)
                VALUES (?, 'CAPACITY_TEST', 'QUEUED', repeat('x', ?))
                """;
        try (Connection connection = POSTGRES.createConnection("");
             PreparedStatement statement = connection.prepareStatement(sql)) {
            statement.setObject(1, UUID.randomUUID());
            statement.setInt(2, valueLength);
            statement.executeUpdate();
        }
    }
}
