package com.omninest.common.maintenance;

import static org.assertj.core.api.Assertions.assertThat;

import com.omninest.common.config.ConfigValueProvider;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.FileTime;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * 日志保留清理的文件边界、保留窗口与配置读取行为验证。
 *
 * <p>所有用例显式注入指向临时目录的绝对扫描路径，避免默认相对路径
 * {@code logs} 解析到进程工作目录造成误删。</p>
 *
 * @author OmniNest
 */
class LogRetentionServiceTest {
    @TempDir
    Path workDir;

    private final Instant now = Instant.parse("2026-09-18T10:00:00Z");

    @Test
    void deletesOnlyExpiredFilesAndKeepsActiveLogAndSymlink() throws IOException {
        Path logs = Files.createDirectories(workDir.resolve("logs"));
        Path activeLog = Files.createFile(logs.resolve("omninest.log"));
        Path oldArchive = aged(logs.resolve("omninest.log.2026-08-01.0.gz"), 30);
        Path freshArchive = aged(logs.resolve("omninest.log.2026-09-17.0.gz"), 1);
        Path oldStray = aged(logs.resolve("dump-2026-07.txt"), 40);
        Path subdirectory = Files.createDirectories(logs.resolve("nested"));
        aged(subdirectory.resolve("nested-old.txt"), 60);

        Path symlink = null;
        try {
            symlink = Files.createSymbolicLink(logs.resolve("link-to-old"), oldArchive);
        } catch (IOException | UnsupportedOperationException e) {
            symlink = null;
        }
        Files.setLastModifiedTime(activeLog, FileTime.from(now.minus(60, ChronoUnit.DAYS)));

        LogRetentionService service = service(activeLog, Map.of());
        int deleted = service.cleanup(now);

        assertThat(deleted).isEqualTo(2);
        assertThat(oldArchive).doesNotExist();
        assertThat(oldStray).doesNotExist();
        assertThat(freshArchive).exists();
        assertThat(activeLog).exists();
        assertThat(subdirectory.resolve("nested-old.txt")).exists();
        if (symlink != null) {
            // 断言用 NOFOLLOW：目标归档已删除，链接本体悬空仍应保留。
            assertThat(java.nio.file.Files.exists(symlink, java.nio.file.LinkOption.NOFOLLOW_LINKS))
                    .isTrue();
        }
    }

    @Test
    void disabledByConfigRemovesNothing() throws IOException {
        Path logs = Files.createDirectories(workDir.resolve("logs"));
        Path activeLog = Files.createFile(logs.resolve("omninest.log"));
        Path oldArchive = aged(logs.resolve("omninest.log.2026-08-01.0.gz"), 30);

        LogRetentionService service = service(
                activeLog, Map.of("log-retention.enabled", "false"));

        assertThat(service.cleanup(now)).isZero();
        assertThat(oldArchive).exists();
    }

    @Test
    void retentionDaysAndExtraScanPathsReadFromConfigCenter() throws IOException {
        Path logs = Files.createDirectories(workDir.resolve("logs"));
        Path tmp = Files.createDirectories(workDir.resolve("tmp-derived"));
        Path activeLog = Files.createFile(logs.resolve("omninest.log"));
        Path barelyOld = aged(logs.resolve("omninest.log.2026-09-16.0.gz"), 3);
        Path oldTemp = aged(tmp.resolve("stale.bin"), 30);

        Map<String, String> values = new HashMap<>();
        values.put("log-retention.retention-days", "2");
        values.put("log-retention.scan-paths", logs + "," + tmp);
        LogRetentionService service = service(activeLog, values);

        assertThat(service.cleanup(now)).isEqualTo(2);
        assertThat(barelyOld).doesNotExist();
        assertThat(oldTemp).doesNotExist();
    }

    @Test
    void missingScanDirectoryIsSkippedQuietly() throws IOException {
        Path logs = Files.createDirectories(workDir.resolve("logs"));
        Path activeLog = Files.createFile(logs.resolve("omninest.log"));

        Map<String, String> values = new HashMap<>();
        values.put("log-retention.scan-paths", workDir.resolve("not-exists").toString());
        LogRetentionService service = service(activeLog, values);

        assertThat(service.cleanup(now)).isZero();
    }

    @Test
    void invalidRetentionDaysFallsBackToDefault() throws IOException {
        Path logs = Files.createDirectories(workDir.resolve("logs"));
        Path activeLog = Files.createFile(logs.resolve("omninest.log"));
        Path oldArchive = aged(logs.resolve("omninest.log.2026-08-01.0.gz"), 30);

        LogRetentionService service = service(
                activeLog, Map.of("log-retention.retention-days", "not-a-number"));

        assertThat(service.cleanup(now)).isEqualTo(1);
        assertThat(oldArchive).doesNotExist();
    }

    private LogRetentionService service(Path activeLog, Map<String, String> overrides) {
        Map<String, String> values = new HashMap<>(overrides);
        values.putIfAbsent("log-retention.scan-paths", activeLog.getParent().toString());
        ConfigValueProvider provider = key -> Optional.ofNullable(values.get(key));
        return new LogRetentionService(provider, null, activeLog.toString());
    }

    private Path aged(Path file, int daysOld) throws IOException {
        Files.createFile(file);
        Files.setLastModifiedTime(file, FileTime.from(now.minus(daysOld, ChronoUnit.DAYS)));
        return file;
    }
}
