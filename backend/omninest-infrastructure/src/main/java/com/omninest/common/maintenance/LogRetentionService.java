package com.omninest.common.maintenance;

import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.config.RuntimeConfigCache;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.FileTime;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Optional;
import java.util.stream.Stream;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 容器内日志与临时文件保留清理（各角色容器自清理，不设角色门控）。
 *
 * <p>日志归档由 logback 滚动策略主闸管理；本任务作为兜底，每日清理
 * {@code log-retention.scan-paths} 目录（默认 {@code logs/}，相对工作目录）
 * 下超过保留期的普通文件，跳过当前活跃日志与符号链接。三个配置中心键
 * （log-retention.enabled / retention-days / scan-paths）支持热更新：
 * 调度每次执行时重新读取。</p>
 *
 * @author OmniNest
 */
@Component
public class LogRetentionService {
    private static final Logger log = LoggerFactory.getLogger(LogRetentionService.class);

    private static final String ENABLED_KEY = "log-retention.enabled";
    private static final String RETENTION_DAYS_KEY = "log-retention.retention-days";
    private static final String SCAN_PATHS_KEY = "log-retention.scan-paths";
    private static final int MIN_RETENTION_DAYS = 1;
    private static final int MAX_RETENTION_DAYS = 365;
    private static final int DEFAULT_RETENTION_DAYS = 14;
    private static final String DEFAULT_SCAN_PATHS = "logs";

    private final ConfigValueProvider configValueProvider;
    private final RuntimeConfigCache runtimeConfigCache;
    private final Path activeLogPath;

    /**
     * 创建保留清理服务。
     *
     * @param configValueProvider 配置中心读取函数
     * @param runtimeConfigCache 运行时配置缓存（可为 null）
     * @param activeLogPath 当前活跃日志文件路径（logging.file.name）
     */
    @Autowired
    public LogRetentionService(
            ConfigValueProvider configValueProvider,
            RuntimeConfigCache runtimeConfigCache,
            @Value("${logging.file.name:logs/omninest.log}") String activeLogPath
    ) {
        this.configValueProvider = configValueProvider;
        this.runtimeConfigCache = runtimeConfigCache;
        this.activeLogPath = Path.of(activeLogPath).toAbsolutePath().normalize();
    }

    /**
     * 每日清理入口（错峰 4:15，避开 FileCleanupService 的 4:00/4:30）。
     */
    @Scheduled(cron = "0 15 4 * * *")
    public void cleanupDaily() {
        cleanup(Instant.now());
    }

    /**
     * 清理扫描目录下超过保留期的普通文件。
     *
     * @param now 当前时间（便于测试注入）
     * @return 删除的文件数
     */
    public int cleanup(Instant now) {
        if (!isEnabled()) {
            return 0;
        }
        int retentionDays = retentionDays();
        Instant cutoff = now.minus(retentionDays, ChronoUnit.DAYS);
        int deleted = 0;
        for (String rawPath : scanPaths()) {
            deleted += cleanupDirectory(rawPath, cutoff);
        }
        if (deleted > 0) {
            log.info("日志保留清理完成: deleted={}, retentionDays={}", deleted, retentionDays);
        }
        return deleted;
    }

    private int cleanupDirectory(String rawPath, Instant cutoff) {
        Path dir = Path.of(rawPath).toAbsolutePath().normalize();
        if (!Files.isDirectory(dir)) {
            return 0;
        }
        int deleted = 0;
        try (Stream<Path> entries = Files.list(dir)) {
            for (Path entry : entries.toList()) {
                if (Files.isSymbolicLink(entry)) {
                    continue;
                }
                if (!Files.isRegularFile(entry)) {
                    continue;
                }
                if (entry.toAbsolutePath().normalize().equals(activeLogPath)) {
                    continue;
                }
                if (isOlderThan(entry, cutoff)) {
                    try {
                        Files.deleteIfExists(entry);
                        deleted++;
                    } catch (IOException e) {
                        log.warn("日志保留清理删除失败: path={}", entry.getFileName(), e);
                    }
                }
            }
        } catch (IOException e) {
            log.warn("日志保留清理扫描失败: dir={}", rawPath, e);
        }
        return deleted;
    }

    private boolean isOlderThan(Path file, Instant cutoff) {
        try {
            FileTime modified = Files.getLastModifiedTime(file);
            return modified.toInstant().isBefore(cutoff);
        } catch (IOException e) {
            return false;
        }
    }

    private boolean isEnabled() {
        return configuredValue(ENABLED_KEY)
                .map(value -> Boolean.parseBoolean(value.trim()))
                .orElse(true);
    }

    private int retentionDays() {
        int configured = configuredValue(RETENTION_DAYS_KEY)
                .map(String::trim)
                .map(value -> {
                    try {
                        return Integer.parseInt(value);
                    } catch (NumberFormatException e) {
                        return DEFAULT_RETENTION_DAYS;
                    }
                })
                .orElse(DEFAULT_RETENTION_DAYS);
        return Math.clamp(configured, MIN_RETENTION_DAYS, MAX_RETENTION_DAYS);
    }

    private List<String> scanPaths() {
        String raw = configuredValue(SCAN_PATHS_KEY).orElse(DEFAULT_SCAN_PATHS);
        return Stream.of(raw.split(","))
                .map(String::trim)
                .filter(path -> !path.isEmpty())
                .toList();
    }

    private Optional<String> configuredValue(String key) {
        if (configValueProvider == null) {
            return Optional.empty();
        }
        Optional<String> cached = runtimeConfigCache == null
                ? Optional.empty()
                : runtimeConfigCache.get(key);
        return cached.or(() -> configValueProvider.findByKey(key));
    }
}
