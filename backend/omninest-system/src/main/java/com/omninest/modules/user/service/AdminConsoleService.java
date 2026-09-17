package com.omninest.modules.user.service;

import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.modules.user.domain.UserStatus;
import com.omninest.common.security.Roles;
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
import com.sun.management.OperatingSystemMXBean;
import java.io.File;
import java.lang.management.ManagementFactory;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import lombok.RequiredArgsConstructor;
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
        return new AdminConsoleSummaryDto.UserStats(
                authUserRepository.count(),
                authUserRepository.countByStatus(UserStatus.ACTIVE.getValue()),
                authUserRepository.countByStatus(UserStatus.DISABLED.getValue()),
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
        long hot = configs.stream().filter(config -> "HOT".equals(config.refreshScope())).count();
        long nextTask = configs.stream().filter(config -> "NEXT_TASK".equals(config.refreshScope())).count();
        long restartRequired = configs.stream()
                .filter(config -> "RESTART_REQUIRED".equals(config.refreshScope()))
                .count();
        return new AdminConsoleSummaryDto.ConfigStats(configs.size(), hot, nextTask, restartRequired);
    }

    private AdminConsoleSummaryDto.TaskStats taskStats() {
        long queued = taskRecordRepository.countByStatus(TaskStatus.QUEUED.getValue());
        long running = taskRecordRepository.countByStatus(TaskStatus.RUNNING.getValue());
        long completed = taskRecordRepository.countByStatus(TaskStatus.COMPLETED.getValue());
        long failed = taskRecordRepository.countByStatus(TaskStatus.FAILED.getValue());
        long cancelled = taskRecordRepository.countByStatus(TaskStatus.CANCELLED.getValue());
        long dlq = taskRecordRepository.countByStatus(TaskStatus.DLQ.getValue());
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
        return List.of(
                new AdminConsoleSummaryDto.HealthItem("API 服务", "UP", "管理接口可访问"),
                new AdminConsoleSummaryDto.HealthItem("用户中心", "UP", userStats.total() + " 个账号"),
                new AdminConsoleSummaryDto.HealthItem("配置中心", "UP", configStats.hot() + " 个热更新配置"),
                new AdminConsoleSummaryDto.HealthItem("任务队列", taskStatus, taskStats.running() + " 个运行中任务"),
                new AdminConsoleSummaryDto.HealthItem("对象存储", "UP", storageStats.objectCount() + " 个对象")
        );
    }

    /**
     * 返回管理后台仪表盘所需的分析数据，包含时间序列指标与系统负载快照。
     */
    @Transactional(readOnly = true)
    public AdminAnalyticsDto analytics(int days) {
        return new AdminAnalyticsDto(
                toDailyMetrics(analyticsRepository.dailyUserGrowth(days)),
                toDailyTaskMetrics(analyticsRepository.dailyTaskThroughput(days)),
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
     */
    private AdminAnalyticsDto.SystemLoadSnapshot systemLoadSnapshot() {
        Runtime rt = Runtime.getRuntime();
        long totalMemory = rt.totalMemory();
        long freeMemory = rt.freeMemory();
        long usedMemory = totalMemory - freeMemory;
        double memoryUsage = (double) usedMemory / totalMemory * 100;
        double jvmHeapUsage = memoryUsage;
        // CPU 和磁盘使用通过 ManagementFactory 获取
        OperatingSystemMXBean osBean =
                (OperatingSystemMXBean) ManagementFactory.getOperatingSystemMXBean();
        double cpuUsage = osBean.getSystemCpuLoad() * 100;
        File root = new File("/");
        long totalSpace = root.getTotalSpace();
        long freeSpace = root.getFreeSpace();
        double diskUsage = totalSpace > 0 ? (1.0 - (double) freeSpace / totalSpace) * 100 : 0;
        return new AdminAnalyticsDto.SystemLoadSnapshot(
                Math.max(0, cpuUsage), Math.max(0, memoryUsage), Math.max(0, diskUsage), Math.max(0, jvmHeapUsage)
        );
    }
}
