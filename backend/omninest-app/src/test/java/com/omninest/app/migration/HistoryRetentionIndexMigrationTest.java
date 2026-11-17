package com.omninest.app.migration;

import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.Test;

/**
 * 系统历史保留索引迁移脚本测试。
 *
 * @author OmniNest
 */
class HistoryRetentionIndexMigrationTest {

    @Test
    void migrationDefinesAuditAndTaskCleanupIndexes() throws IOException {
        String resource = "db/migration/V001__init_schema.sql";
        try (InputStream input = Thread.currentThread()
                .getContextClassLoader()
                .getResourceAsStream(resource)) {
            Assertions.assertThat(input).isNotNull();
            String sql = new String(input.readAllBytes(), StandardCharsets.UTF_8)
                    .toLowerCase()
                    .replaceAll("\\s+", " ");
            Assertions.assertThat(sql)
                    .contains("idx_audit_logs_created_at")
                    .contains("on \"omni\".\"audit_logs\" using btree ( \"created_at\"")
                    .contains("idx_sys_tasks_status_updated")
                    .contains("on \"omni\".\"sys_tasks\" using btree ( \"status\"")
                    .contains("\"updated_at\" \"pg_catalog\".\"timestamptz_ops\"")
                    .doesNotContain("foreign key")
                    .doesNotContain("references ");
        }
    }
}
