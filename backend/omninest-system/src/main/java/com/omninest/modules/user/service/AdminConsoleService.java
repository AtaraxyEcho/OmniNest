package com.omninest.modules.user.service;

import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.modules.user.domain.UserStatus;
import com.omninest.common.security.Roles;
import com.omninest.modules.configcenter.domain.RefreshScope;
import com.omninest.modules.configcenter.dto.ConfigEntryDto;
import com.omninest.modules.configcenter.service.ConfigCenterService;
import com.omninest.modules.quota.port.StorageMetricsQuery;
import com.omninest.modules.quota.port.StorageMetricsSnapshot;
import com.omninest.modules.quota.service.StorageQuotaService;
import com.omninest.modules.user.domain.AuthPermission;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.dto.AdminAnalyticsDto;
import com.omninest.modules.user.dto.AdminConsoleSummaryDto;
import com.omninest.modules.user.repository.AdminAnalyticsRepository;
import com.omninest.modules.user.repository.AuditLogAdminRepository;
import com.omninest.modules.user.repository.TaskRecordAdminRepository;
import com.omninest.modules.user.repository.AuthRoleRepository;
import com.omninest.modules.user.repository.AuthUserRepository;
import com.omninest.modules.user.port.ExternalStorageAdministration;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.health.actuate.endpoint.HealthEndpoint;
import org.springframework.boot.health.contributor.Status;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 管理控制台聚合服务，组合用户、配置、任务和存储指标。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class AdminConsoleService {
    private final AuthUserRepository authUserRepository;
    private final AuthRoleRepository authRoleRepository;
    private final ConfigCenterService configCenterService;
    private final TaskRecordAdminRepository taskRecordRepository;
    private final ExternalStorageAdministration externalStorageAdministration;
    private final AuditLogAdminRepository auditLogRepository;
    private final StorageMetricsQuery storageMetricsQuery;
    private final AdminAnalyticsRepository analyticsRepository;
    private final StorageQuotaService storageQuotaService;
    private final SystemMetricsCollector systemMetricsCollector;
    private final HealthEndpoint healthEndpoint;
    private final SystemInstanceConfigService systemInstanceConfigService;

    @Transactional(readOnly = true)
    public AdminConsoleSummaryDto summary() {
        List<AuthRole> roles = loadRoles();
        List<ConfigEntryDto> configs = configCenterService.list();
        AdminConsoleSummaryDto.UserStats userStats = userStats();
        AdminConsoleSummaryDto.ConfigStats configStats = configStats(configs);
        AdminConsoleSummaryDto.TaskStats taskStats = taskStats();
        AdminConsoleSummaryDto.StorageStats storageStats = storageStats();
        return new AdminConsoleSummaryDto(
                userStats,
                roleSummaries(roles),
                configStats,
                taskStats,
                storageStats,
                health(userStats, configStats, taskStats, storageStats)
        );
    }

    @Transactional(readOnly = true)
    public List<AdminConsoleSummaryDto.RoleSummary> roles() {
        return roleSummaries(loadRoles());
    }

    private List<AuthRole> loadRoles() {
        return authRoleRepository.findAllWithPermissions(Sort.by(Sort.Direction.ASC, "code"));
    }

    private AdminConsoleSummaryDto.UserStats userStats() {
        Map<String, Long> roleCounts = new LinkedHashMap<>();
        roleCounts.put(Roles.SUPER_ADMIN, 0L);
        roleCounts.put(Roles.ADMIN, 0L);
        roleCounts.put(Roles.MEMBER, 0L);
        roleCounts.put(Roles.GUEST, 0L);
        for (Object[] row : authUserRepository.countUsersByEnabledRole()) {
            if (row.length >= 2 && row[0] != null) {
                roleCounts.put(row[0].toString(), toLong(row[1]));
            }
        }
        Map<String, Long> counts = new LinkedHashMap<>();
        for (Object[] row : authUserRepository.countUsersByStatus()) {
            counts.put(row[0].toString(), toLong(row[1]));
        }
        long total = counts.values().stream().mapToLong(Long::longValue).sum();
        return new AdminConsoleSummaryDto.UserStats(
                total,
                counts.getOrDefault(UserStatus.ACTIVE.getValue(), 0L),
                counts.getOrDefault(UserStatus.DISABLED.getValue(), 0L),
                roleCounts
        );
    }

    private List<AdminConsoleSummaryDto.RoleSummary> roleSummaries(List<AuthRole> roles) {
        return roles.stream()
                .map(role -> new AdminConsoleSummaryDto.RoleSummary(
                        role.getCode(),
                        role.getName(),
                        role.getDescription(),
                        role.isBuiltIn(),
                        role.isEnabled(),
                        enabledPermissions(role).size(),
                        enabledPermissions(role)
                ))
                .toList();
    }

    private List<String> enabledPermissions(AuthRole role) {
        return role.getPermissions().stream()
                .filter(AuthPermission::isEnabled)
                .map(AuthPermission::getCode)
                .sorted(Comparator.naturalOrder())
                .toList();
    }

    private AdminConsoleSummaryDto.ConfigStats configStats(List<ConfigEntryDto> configs) {
        // 统计口径直接取枚举，避免字面量与数据库 CHECK、枚举三处各写一份而漂移。
        long hot = configs.stream()
                .filter(config -> RefreshScope.HOT.getValue().equals(config.refreshScope()))
                .count();
        long nextTask = configs.stream()
                .filter(config -> RefreshScope.NEXT_TASK.getValue().equals(config.refreshScope()))
                .count();
        long restartRequired = configs.stream()
                .filter(config -> RefreshScope.RESTART_REQUIRED.getValue().equals(config.refreshScope()))
                .count();
        return new AdminConsoleSummaryDto.ConfigStats(configs.size(), hot, nextTask, restartRequired);
    }

    private AdminConsoleSummaryDto.TaskStats taskStats() {
        Map<String, Long> counts = taskRecordRepository.countGroupedByStatus();
        // RETRY_WAIT 同样是排队态：漏掉它会让总数与 queued 都低估。
        long queued = counts.getOrDefault(TaskStatus.QUEUED.getValue(), 0L)
                + counts.getOrDefault(TaskStatus.RETRY_WAIT.getValue(), 0L);
        long running = counts.getOrDefault(TaskStatus.RUNNING.getValue(), 0L);
        long completed = counts.getOrDefault(TaskStatus.COMPLETED.getValue(), 0L);
        long failed = counts.getOrDefault(TaskStatus.FAILED.getValue(), 0L);
        // DISCARDED 是管理员显式丢弃死信的处置结果，与主动取消同性质，归入 cancelled 桶且不计入 failed/dlq。
        long cancelled = counts.getOrDefault(TaskStatus.CANCELLED.getValue(), 0L)
                + counts.getOrDefault(TaskStatus.DISCARDED.getValue(), 0L);
        long dlq = counts.getOrDefault(TaskStatus.DLQ.getValue(), 0L);
        return new AdminConsoleSummaryDto.TaskStats(
                queued + running + completed + failed + cancelled + dlq,
                queued,
                running,
                completed,
                failed,
                cancelled,
                dlq
        );
    }

    private AdminConsoleSummaryDto.StorageStats storageStats() {
        StorageMetricsSnapshot metrics = storageMetricsQuery.systemMetrics();
        return new AdminConsoleSummaryDto.StorageStats(
                metrics.fileCount(),
                metrics.folderCount(),
                metrics.objectCount(),
                metrics.usedBytes(),
                externalStorageAdministration.countAccounts()
        );
    }

    private List<AdminConsoleSummaryDto.HealthItem> health(
            AdminConsoleSummaryDto.UserStats userStats,
            AdminConsoleSummaryDto.ConfigStats configStats,
            AdminConsoleSummaryDto.TaskStats taskStats,
            AdminConsoleSummaryDto.StorageStats storageStats
    ) {
        String taskStatus = taskStats.failed() + taskStats.dlq() > 0 ? "WARN" : "UP";
        String storageStatus = componentStatus("minio");
        return List.of(
                new AdminConsoleSummaryDto.HealthItem("API 服务", "UP", "管理接口可访问"),
                new AdminConsoleSummaryDto.HealthItem("用户中心", "UP", userStats.total() + " 个账号"),
                new AdminConsoleSummaryDto.HealthItem("配置中心", "UP", configStats.hot() + " 个热更新配置"),
                new AdminConsoleSummaryDto.HealthItem("任务队列", taskStatus, taskStats.running() + " 个运行中任务"),
                new AdminConsoleSummaryDto.HealthItem(
                        "对象存储", storageStatus, storageStats.objectCount() + " 个对象")
        );
    }

    private String componentStatus(String componentName) {
        try {
            var health = healthEndpoint.healthForPath(componentName);
            if (health == null) {
                return "DOWN";
            }
            return Status.UP.equals(health.getStatus()) ? "UP" : "WARN";
        } catch (RuntimeException exception) {
            return "DOWN";
        }
    }

    /**
     * 返回管理后台仪表盘所需的分析数据，包含时间序列指标与系统负载快照。
     */
    @Transactional(readOnly = true)
    public AdminAnalyticsDto analytics(int days) {
        return new AdminAnalyticsDto(
                toDailyMetrics(analyticsRepository.dailyUserGrowth(days)),
                toDailyTaskMetrics(analyticsRepository.dailyTaskThroughput(
                        days, systemInstanceConfigService.timeZone().getId())),
                toDailyMetrics(analyticsRepository.dailyStorageGrowth(days)),
                systemLoadSnapshot()
        );
    }

    private List<AdminAnalyticsDto.DailyMetric> toDailyMetrics(List<Object[]> rows) {
        return rows.stream()
                .map(row -> new AdminAnalyticsDto.DailyMetric(
                        row[0].toString(), toLong(row[1])))
                .toList();
    }

    private List<AdminAnalyticsDto.DailyTaskMetric> toDailyTaskMetrics(List<Object[]> rows) {
        return rows.stream()
                .map(row -> new AdminAnalyticsDto.DailyTaskMetric(
                        row[0].toString(), toLong(row[1]), toLong(row[2]), toLong(row[3])))
                .toList();
    }

    private long toLong(Object value) {
        if (value instanceof Number number) {
            return number.longValue();
        }
        return Long.parseLong(value.toString());
    }

    /**
     * 重算所有用户的存储用量。
     * 从 file_objects + file_nodes 实际数据重新计算，覆盖 auth_users.used_bytes 缓存值。
     * 用于修复手动删除数据后计数器漂移的问题。
     */
    @Transactional(rollbackFor = Exception.class)
    public int recalculateStorageUsage() {
        return storageQuotaService.recalculateAllUsages();
    }

    /**
     * 采集当前系统负载快照（CPU、内存、磁盘、JVM 堆使用率）。
     *
     * <p>口径与运维页共用 {@link SystemMetricsCollector}，两个面板必须给出同一个数。</p>
     */
    private AdminAnalyticsDto.SystemLoadSnapshot systemLoadSnapshot() {
        SystemMetricsCollector.Snapshot metrics = systemMetricsCollector.collect();
        return new AdminAnalyticsDto.SystemLoadSnapshot(
                metrics.cpuUsagePercent(),
                metrics.systemMemoryUsagePercent(),
                metrics.diskUsagePercent(),
                metrics.heapUsagePercent()
        );
    }
}
