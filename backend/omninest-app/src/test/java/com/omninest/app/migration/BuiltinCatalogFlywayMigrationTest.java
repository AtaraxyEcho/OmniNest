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
 * 在真实 PostgreSQL 中验证空库安装依赖的内置目录。
 *
 * @author OmniNest
 */
@Testcontainers(disabledWithoutDocker = true)
class BuiltinCatalogFlywayMigrationTest {
    private static final String IMAGE = "postgres:18-alpine";

    @Container
    private static final PostgreSQLContainer<?> POSTGRES = new PostgreSQLContainer<>(IMAGE)
            .withDatabaseName("omninest_builtin_catalog")
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
    void catalogContainsRequiredRolesPermissionsAndMappings() throws SQLException {
        Assertions.assertThat(countObjects("SELECT count(*) FROM omni.auth_roles")).isEqualTo(4);
        Assertions.assertThat(countObjects("SELECT count(*) FROM omni.auth_permissions")).isEqualTo(18);
        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM (
                    VALUES
                        ('SUPER_ADMIN'),
                        ('ADMIN'),
                        ('MEMBER'),
                        ('GUEST')
                ) expected(code)
                FULL JOIN omni.auth_roles actual USING (code)
                WHERE expected.code IS NULL
                   OR actual.code IS NULL
                   OR NOT actual.built_in
                   OR NOT actual.enabled
                """)).isZero();
        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM (
                    VALUES
                        ('profile:read'),
                        ('profile:write'),
                        ('file:read'),
                        ('file:write'),
                        ('media:read'),
                        ('media:write'),
                        ('media:library:manage'),
                        ('photo:read'),
                        ('photo:write'),
                        ('photo:admin'),
                        ('backdrop:read'),
                        ('backdrop:write'),
                        ('task:read'),
                        ('task:admin'),
                        ('system:config:read'),
                        ('system:config:manage'),
                        ('system:user:read'),
                        ('system:user:manage')
                ) expected(code)
                FULL JOIN omni.auth_permissions actual USING (code)
                WHERE expected.code IS NULL
                   OR actual.code IS NULL
                   OR NOT actual.enabled
                """)).isZero();
        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM omni.auth_role_permissions role_permission
                LEFT JOIN omni.auth_roles role_definition ON role_definition.id = role_permission.role_id
                LEFT JOIN omni.auth_permissions permission_definition
                  ON permission_definition.id = role_permission.permission_id
                WHERE role_definition.id IS NULL
                   OR permission_definition.id IS NULL
                """)).isZero();
        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM (
                    VALUES
                        ('GUEST', 4),
                        ('MEMBER', 11),
                        ('ADMIN', 17),
                        ('SUPER_ADMIN', 18)
                ) expected(role_code, permission_count)
                LEFT JOIN (
                    SELECT role_definition.code AS role_code, count(*)::integer AS permission_count
                    FROM omni.auth_roles role_definition
                    JOIN omni.auth_role_permissions role_permission
                      ON role_permission.role_id = role_definition.id
                    GROUP BY role_definition.code
                ) actual ON actual.role_code = expected.role_code
                WHERE actual.permission_count IS DISTINCT FROM expected.permission_count
                """)).isZero();
        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM omni.auth_roles role_definition
                JOIN omni.auth_role_permissions role_permission
                  ON role_permission.role_id = role_definition.id
                JOIN omni.auth_permissions permission_definition
                  ON permission_definition.id = role_permission.permission_id
                WHERE role_definition.code = 'MEMBER'
                  AND permission_definition.code = 'task:admin'
                """)).isZero();
        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM omni.auth_roles role_definition
                JOIN omni.auth_role_permissions role_permission
                  ON role_permission.role_id = role_definition.id
                JOIN omni.auth_permissions permission_definition
                  ON permission_definition.id = role_permission.permission_id
                WHERE role_definition.code IN ('ADMIN', 'SUPER_ADMIN')
                  AND permission_definition.code = 'task:admin'
                """)).isEqualTo(2);
        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM omni.auth_roles role_definition
                JOIN omni.auth_role_permissions role_permission
                  ON role_permission.role_id = role_definition.id
                JOIN omni.auth_permissions permission_definition
                  ON permission_definition.id = role_permission.permission_id
                WHERE role_definition.code = 'MEMBER'
                  AND permission_definition.code = 'task:read'
                """)).isEqualTo(1);
    }

    @Test
    void catalogContainsCompleteNotificationTypeDirectory() throws SQLException {
        Assertions.assertThat(countObjects("SELECT count(*) FROM omni.notification_types")).isEqualTo(11);
        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM (
                    VALUES
                        ('TASK_COMPLETED'),
                        ('TASK_FAILED'),
                        ('SHARE_ACCESS'),
                        ('SYSTEM_MESSAGE'),
                        ('MEDIA_SCRAPED'),
                        ('SHARE_ACCESSED'),
                        ('QUOTA_WARNING'),
                        ('NEW_DEVICE_LOGIN'),
                        ('PASSWORD_CHANGED'),
                        ('SECURITY_THREAT'),
                        ('SECURITY_SCAN_FAILED')
                ) expected(type_code)
                FULL JOIN omni.notification_types actual USING (type_code)
                WHERE expected.type_code IS NULL
                   OR actual.type_code IS NULL
                   OR NOT actual.enabled
                """)).isZero();
    }

    @Test
    void catalogContainsCompleteRuntimeConfigurationDirectory() throws SQLException {
        Assertions.assertThat(countObjects("SELECT count(*) FROM omni.config_entries")).isEqualTo(69);
        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM (
                    VALUES
                        ('app.version.download-url'),
                        ('app.version.latest'),
                        ('app.version.release-notes-url'),
                        ('auth.two-factor.required-roles'),
                        ('clamav.timeout-millis'),
                        ('security.quarantine.retention-days'),
                        ('media.transcode.enabled'),
                        ('media.import.enabled'),
                        ('reader.import.enabled'),
                        ('photo.backup'),
                        ('photo.geo.rate'),
                        ('photo.geo.offline'),
                        ('photo.geo.nominatim'),
                        ('photo.geo.max-distance-km'),
                        ('photo.geo.import.batch-size'),
                        ('photo.geo.import.auto'),
                        ('storage.quota.default'),
                        ('storage.quota.warning'),
                        ('share.enabled'),
                        ('share.max-bytes'),
                        ('upload.rate.enabled'),
                        ('security.rate-limit'),
                        ('clamav.enabled'),
                        ('clamav.host'),
                        ('clamav.port'),
                        ('weather.enabled'),
                        ('media.tmdb.enabled'),
                        ('media.tmdb.key'),
                        ('media.tmdb.token'),
                        ('media.tmdb.url'),
                        ('media.tmdb.lang'),
                        ('media.tmdb.timeout'),
                        ('media.tmdb.strategy'),
                        ('media.tmdb.limit'),
                        ('media.tmdb.adult'),
                        ('reader.gbooks.enabled'),
                        ('reader.gbooks.url'),
                        ('reader.gbooks.lang'),
                        ('reader.gbooks.limit'),
                        ('reader.gbooks.timeout'),
                        ('reader.gbooks.key'),
                        ('reader.openlib.enabled'),
                        ('reader.openlib.url'),
                        ('reader.openlib.lang'),
                        ('music.musicbrainz.enabled'),
                        ('music.import.enabled'),
                        ('music.musicbrainz.url'),
                        ('music.musicbrainz.ua'),
                        ('music.musicbrainz.cover-url'),
                        ('music.online.enabled'),
                        ('music.netease.enabled'),
                        ('music.netease.url'),
                        ('music.netease.hosts'),
                        ('music.qq.enabled'),
                        ('music.qq.u-url'),
                        ('music.qq.c-url'),
                        ('music.qq.hosts'),
                        ('photo.ai.enabled'),
                        ('photo.ai.url'),
                        ('photo.ai.timeout'),
                        ('backdrop.max-image-bytes'),
                        ('backdrop.max-video-bytes'),
                        ('backdrop.max-assets-per-user'),
                        ('backdrop.upload.rate-per-hour'),
                        ('weather.qweather.project'),
                        ('weather.qweather.credential'),
                        ('weather.qweather.url'),
                        ('weather.qweather.key'),
                        ('weather.location')
                ) expected(config_key)
                FULL JOIN omni.config_entries actual USING (config_key)
                WHERE expected.config_key IS NULL
                   OR actual.config_key IS NULL
                   OR actual.refresh_scope <> 'HOT'
                """)).isZero();
        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM omni.config_entries
                WHERE is_sensitive
                  AND config_key IN (
                    'media.tmdb.key',
                    'media.tmdb.token',
                    'reader.gbooks.key',
                    'weather.qweather.key'
                  )
                  AND config_value = ''
                """)).isEqualTo(4);
    }

    @Test
    void catalogInitializesSharedSpacePermissionsAndUsage() throws SQLException {
        Assertions.assertThat(countObjects("SELECT count(*) FROM omni.shared_space_permissions")).isEqualTo(4);
        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM omni.shared_space_permissions shared_permission
                LEFT JOIN omni.auth_roles role_definition ON role_definition.id = shared_permission.role_id
                WHERE role_definition.id IS NULL
                """)).isZero();
        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM (
                    VALUES
                        ('SUPER_ADMIN', true, true, true, true, true, true, true, true),
                        ('ADMIN', true, true, true, true, true, true, true, true),
                        ('MEMBER', true, true, true, true, false, true, true, true),
                        ('GUEST', true, false, true, false, false, false, false, false)
                ) expected(
                    role_code,
                    can_browse,
                    can_upload,
                    can_download,
                    can_delete_own,
                    can_delete_any,
                    can_move_to,
                    can_move_from,
                    can_create_folder
                )
                JOIN omni.auth_roles role_definition ON role_definition.code = expected.role_code
                LEFT JOIN omni.shared_space_permissions actual ON actual.role_id = role_definition.id
                WHERE actual.id IS NULL
                   OR actual.can_browse IS DISTINCT FROM expected.can_browse
                   OR actual.can_upload IS DISTINCT FROM expected.can_upload
                   OR actual.can_download IS DISTINCT FROM expected.can_download
                   OR actual.can_delete_own IS DISTINCT FROM expected.can_delete_own
                   OR actual.can_delete_any IS DISTINCT FROM expected.can_delete_any
                   OR actual.can_move_to IS DISTINCT FROM expected.can_move_to
                   OR actual.can_move_from IS DISTINCT FROM expected.can_move_from
                   OR actual.can_create_folder IS DISTINCT FROM expected.can_create_folder
                """)).isZero();
        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM omni.shared_space_usage
                WHERE used_bytes = 0
                  AND file_count = 0
                """)).isEqualTo(1);
    }

    @Test
    void catalogInitializesPendingSystemInstance() throws SQLException {
        Assertions.assertThat(countObjects("""
                SELECT count(*)
                FROM omni.system_instances
                WHERE id = '00000000-0000-0000-0000-000000000001'
                  AND installation_id IS NOT NULL
                  AND setup_state = 'SETUP_REQUIRED'
                  AND instance_name = 'OmniNest'
                  AND default_locale = 'zh-CN'
                  AND default_timezone = 'Asia/Shanghai'
                """)).isEqualTo(1);
        Assertions.assertThat(countObjects("SELECT count(*) FROM omni.auth_users")).isZero();
        Assertions.assertThat(countObjects("SELECT count(*) FROM omni.auth_user_roles")).isZero();
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
