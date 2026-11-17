package com.omninest.app.migration;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.Test;

/**
 * 同步事件迁移脚本静态约束测试。
 *
 * @author OmniNest
 */
class SyncEventMigrationScriptTest {

    @Test
    void migrationDefinesRequiredTablesWithoutDatabaseRelations() throws IOException {
        String resource = "db/migration/V001__init_schema.sql";
        try (InputStream input = Thread.currentThread()
                .getContextClassLoader()
                .getResourceAsStream(resource)) {
            assertThat(input).as("迁移脚本必须存在").isNotNull();
            String sql = new String(input.readAllBytes(), StandardCharsets.UTF_8).toUpperCase();
            assertThat(sql).contains("SYNC_EVENTS", "SYNC_EVENT_CHECKPOINTS");
            assertThat(sql).contains("IDX_SYNC_EVENTS_RECIPIENT_SEQUENCE");
            assertThat(sql)
                    .doesNotContainPattern("\\bREFERENCES\\s+")
                    .doesNotContain("FOREIGN KEY", "ON DELETE", "ON UPDATE");
        }
    }
}
