package com.omninest.app.migration;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 基线索引与存量升级脚本的对齐闸门。
 *
 * <p>新安装走 {@code V001__init_schema.sql}，已部署环境只执行
 * {@code deploy/db/upgrade-baseline-*.sql} 后 repair 校验和。两份路径一旦漂移，
 * 存量环境会在不知不觉中退化为全表扫描，而新装环境完全正常，属于典型的
 * "只在老环境坏掉"的缺陷。这里把 V001 尾部索引集合与升级脚本钉在一起。</p>
 *
 * @author OmniNest
 */
class UpgradeBaselineIndexParityRatchetTest {

    private static final String TAIL_MARKER = "模糊检索索引（pg_trgm）";

    private static final Pattern INDEX_NAME = Pattern.compile("CREATE INDEX (?:CONCURRENTLY )?IF NOT EXISTS \"([^\"]+)\"|CREATE INDEX \"([^\"]+)\"");

    @Test
    @DisplayName("V001 尾部索引必须全部登记到升级脚本")
    void everyTailIndexMustAppearInUpgradeScripts() throws IOException {
        String baseline = readBaseline();
        int marker = baseline.lastIndexOf(TAIL_MARKER);
        assertThat(marker)
                .as("V001 尾部索引段标记缺失，无法判定对齐范围")
                .isGreaterThan(0);

        Set<String> tailIndexes = indexNames(baseline.substring(marker));
        assertThat(tailIndexes).isNotEmpty();

        String upgradeText = String.join("\n", upgradeScripts());
        List<String> missing = new ArrayList<>();
        for (String index : tailIndexes) {
            if (!upgradeText.contains("\"" + index + "\"")) {
                missing.add(index);
            }
        }
        assertThat(missing)
                .as("存量环境升级脚本缺少 V001 尾部索引，升级后会全表扫描")
                .isEmpty();
    }

    @Test
    @DisplayName("CONCURRENTLY 不得包在 BEGIN...COMMIT 事务块内")
    void concurrentIndexesMustStayOutsideTransactionBlocks() throws IOException {
        for (String text : upgradeScripts()) {
            boolean inTransaction = false;
            for (String line : text.split("\\R")) {
                String normalized = line.trim().toUpperCase();
                if (normalized.equals("BEGIN;")) {
                    inTransaction = true;
                } else if (normalized.equals("COMMIT;")) {
                    inTransaction = false;
                } else if (inTransaction && normalized.contains("CONCURRENTLY")) {
                    assertThat(false)
                            .as("PostgreSQL 禁止在事务块内执行 CREATE INDEX CONCURRENTLY")
                            .isTrue();
                }
            }
        }
    }

    @Test
    @DisplayName("任务与会话清理的复合索引必须留在基线中")
    void taskAndSessionCleanupIndexesMustStay() throws IOException {
        String baseline = readBaseline();
        assertThat(baseline)
                .contains("\"idx_sys_tasks_owner_created_at\"")
                .contains("\"idx_sys_tasks_owner_status_created_at\"")
                .contains("\"idx_sys_tasks_status_created_at\"")
                .contains("\"idx_sessions_revoked_at\"");
    }

    private Set<String> indexNames(String text) {
        Set<String> names = new LinkedHashSet<>();
        Matcher matcher = INDEX_NAME.matcher(text);
        while (matcher.find()) {
            String name = matcher.group(1) != null ? matcher.group(1) : matcher.group(2);
            if (name != null) {
                names.add(name);
            }
        }
        return names;
    }

    private String readBaseline() throws IOException {
        String resource = "db/migration/V001__init_schema.sql";
        try (var input = Thread.currentThread().getContextClassLoader().getResourceAsStream(resource)) {
            assertThat(input).as("缺少类路径资源 " + resource).isNotNull();
            return new String(input.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    private List<String> upgradeScripts() throws IOException {
        Path directory = repositoryRoot().resolve("deploy/db");
        List<String> contents = new ArrayList<>();
        try (Stream<Path> files = Files.list(directory)) {
            for (Path file : files
                    .filter(path -> path.getFileName().toString().startsWith("upgrade-baseline-"))
                    .filter(path -> path.getFileName().toString().endsWith(".sql"))
                    .sorted()
                    .toList()) {
                contents.add(Files.readString(file, StandardCharsets.UTF_8));
            }
        }
        assertThat(contents).as("deploy/db 下缺少 upgrade-baseline-*.sql").isNotEmpty();
        return contents;
    }

    private Path repositoryRoot() {
        Path current = Path.of("").toAbsolutePath().normalize();
        for (int depth = 0; depth < 6 && current != null; depth++) {
            if (Files.isDirectory(current.resolve("deploy/db"))) {
                return current;
            }
            current = current.getParent();
        }
        throw new IllegalStateException("无法定位仓库根目录");
    }
}
