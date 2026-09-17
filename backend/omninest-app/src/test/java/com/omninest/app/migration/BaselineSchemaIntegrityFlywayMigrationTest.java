package com.omninest.app.migration;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import org.assertj.core.api.Assertions;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * 在真实 PostgreSQL 中验证当前空库基线的结构完整性。
 *
 * @author OmniNest
 */
@Testcontainers(disabledWithoutDocker = true)
class BaselineSchemaIntegrityFlywayMigrationTest {
    private static final String IMAGE = "postgres:18-alpine";

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_baseline_integrity")
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
    void everyTableHasPrimaryKey() throws SQLException {
        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM pg_class table_definition
                JOIN pg_namespace namespace ON namespace.oid = table_definition.relnamespace
                LEFT JOIN pg_constraint primary_key
                  ON primary_key.conrelid = table_definition.oid
                 AND primary_key.contype = 'p'
                WHERE namespace.nspname = 'omni'
                  AND table_definition.relkind = 'r'
                  AND primary_key.oid IS NULL
                """)).isZero();
    }

    @Test
    void everyConstraintIsValidated() throws SQLException {
        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM pg_constraint
                WHERE connamespace = 'omni'::regnamespace
                  AND NOT convalidated
                """)).isZero();
    }

    @Test
    void baselineContainsRequiredReaderAndTaskIndexes() throws SQLException {
        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM pg_constraint
                WHERE connamespace = 'omni'::regnamespace
                  AND conname IN (
                    'reader_catalog_nodes_pkey',
                    'reader_pages_pkey',
                    'reader_progress_pkey',
                    'uniq_reader_progress_owner_item',
                    'chk_reader_progress_mode',
                    'chk_reader_progress_range'
                  )
                """)).isEqualTo(6);

        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM pg_indexes
                WHERE schemaname = 'omni'
                  AND indexname IN (
                    'idx_reader_catalog_nodes_item',
                    'idx_reader_catalog_nodes_key',
                    'idx_reader_catalog_nodes_parent',
                    'idx_reader_catalog_nodes_source',
                    'idx_reader_pages_catalog',
                    'idx_reader_pages_catalog_key',
                    'idx_reader_pages_item',
                    'idx_reader_pages_source',
                    'idx_reader_pages_source_page',
                    'idx_reader_progress_owner'
                  )
                """)).isEqualTo(10);

        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM pg_indexes
                WHERE schemaname = 'omni'
                  AND indexname IN (
                    'idx_download_offline_tasks_task',
                    'idx_import_tasks_task',
                    'idx_music_scan_jobs_task',
                    'idx_photo_batch_tasks_task',
                    'idx_photo_scan_jobs_task'
                  )
                """)).isEqualTo(5);
    }

    @Test
    void baselineContainsFilePurgeAndTaskOutboxStructures() throws SQLException {
        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM information_schema.tables
                WHERE table_schema = 'omni'
                  AND table_name IN ('file_purge_entries', 'sys_task_dispatches')
                """)).isEqualTo(2);

        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM information_schema.columns
                WHERE table_schema = 'omni'
                  AND (
                    (table_name = 'file_nodes' AND column_name IN (
                      'purge_state', 'purge_task_id', 'purge_requested_at', 'version', 'category'
                    ))
                    OR
                    (table_name = 'sys_tasks' AND column_name IN (
                      'phase', 'resource_type', 'resource_id', 'next_retry_at', 'heartbeat_at'
                    ))
                  )
                """)).isEqualTo(10);

        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM pg_indexes
                WHERE schemaname = 'omni'
                  AND indexname IN (
                    'idx_file_purge_entries_task_status',
                    'uq_file_purge_entries_object',
                    'idx_sys_task_dispatches_available',
                    'idx_sys_task_dispatches_lease',
                    'idx_sys_task_dispatches_task'
                  )
                """)).isEqualTo(5);
    }

    @Test
    void currentMigrationsAreRecordedByFlyway() throws SQLException {
        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM omni.flyway_schema_history
                WHERE version IN ('001', '002')
                  AND success
                """)).isEqualTo(2);
    }

    @Test
    void baselineExcludesRemovedRemoteBackupTable() throws SQLException {
        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM information_schema.tables
                WHERE table_schema = 'omni'
                  AND table_name = 'backup_jobs'
                """)).isZero();
    }

    private int countObjects(String sql) throws SQLException {
        try (Connection connection = POSTGRES.createConnection("");
             Statement statement = connection.createStatement();
             ResultSet result = statement.executeQuery(sql)) {
            Assertions.assertThat(result.next()).isTrue();
            return result.getInt(1);
        }
    }
}
