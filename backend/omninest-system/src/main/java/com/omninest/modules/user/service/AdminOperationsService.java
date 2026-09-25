package com.omninest.modules.user.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.modules.task.domain.TaskStatus;
import com.omninest.common.error.BusinessException;
import com.omninest.common.runtime.WorkerRuntimeRegistry;
import com.omninest.common.runtime.WorkerRuntimeState;
import com.omninest.common.security.Roles;
import com.omninest.common.storage.ObjectStorageBuckets;
import com.omninest.modules.configcenter.dto.ConfigEntryDto;
import com.omninest.modules.configcenter.service.ConfigCenterService;
import com.omninest.modules.task.service.TaskRedispatchService;
import com.omninest.modules.user.domain.AuthActiveSession;
import com.omninest.modules.user.domain.AuthLoginAudit;
import com.omninest.modules.user.domain.AuthPermission;
import com.omninest.modules.user.domain.AuthRole;
import com.omninest.modules.user.domain.AuthUser;
import com.omninest.modules.user.domain.AuditLog;
import com.omninest.modules.user.domain.UserStatus;
import com.omninest.modules.user.dto.AdminConsoleSummaryDto;
import com.omninest.modules.user.dto.AdminOperationsDto;
import com.omninest.modules.user.dto.AdminOperationDescription;
import com.omninest.modules.user.port.ExternalStorageAccountSummary;
import com.omninest.modules.user.port.ExternalStorageAdministration;
import com.omninest.modules.user.repository.ActiveSessionRepository;
import com.omninest.modules.user.repository.AdminConsoleMetricsRepository;
import com.omninest.modules.user.repository.AuditLogAdminRepository;
import com.omninest.modules.user.repository.AuthLoginAuditRepository;
import com.omninest.modules.user.repository.AuthPermissionRepository;
import com.omninest.modules.user.repository.AuthRoleRepository;
import com.omninest.modules.user.repository.AuthUserRepository;
import com.omninest.modules.user.repository.TaskRecordAdminRepository;
import com.sun.management.OperatingSystemMXBean;
import java.io.File;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import java.lang.management.MemoryUsage;
import java.sql.Timestamp;
import java.time.Duration;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.health.actuate.endpoint.HealthEndpoint;
import org.springframework.boot.health.contributor.Status;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 管理控制台操作服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class AdminOperationsService {
    private static final int DEFAULT_TASK_LIMIT = 100;
    private static final int DEFAULT_LOG_LIMIT = 100;
    private static final int DEFAULT_SESSION_LIMIT = 500;
    private static final int DEFAULT_LOGIN_AUDIT_LIMIT = 500;
    private static final Set<String> RETRYABLE_TASK_STATUS = Set.of(
            TaskStatus.FAILED.getValue(),
            TaskStatus.CANCELLED.getValue(),
            TaskStatus.DLQ.getValue()
    );
    private final AuthRoleRepository authRoleRepository;
    private final AuthUserRepository authUserRepository;
    private final AuthPermissionRepository authPermissionRepository;
    private final ConfigCenterService configCenterService;
    private final AdminConsoleMetricsRepository metricsRepository;
    private final TaskRecordAdminRepository taskRecordRepository;
    private final ExternalStorageAdministration externalStorageAdministration;
    private final AuditLogAdminRepository auditLogAdminRepository;
    private final AdminAuditLogService auditLogService;
    private final TaskRedispatchService taskRedispatchService;
    private final ObjectStorageBuckets objectStorageBuckets;
    private final HealthEndpoint healthEndpoint;
    private final ActiveSessionRepository activeSessionRepository;
    private final AuthLoginAuditRepository loginAuditRepository;
    private final SessionRevocationService sessionRevocationService;
    private final UserSessionRevocationService userSessionRevocationService;
    private final WorkerRuntimeRegistry workerRuntimeRegistry;

    @Transactional(readOnly = true)
    public AdminOperationsDto.RoleManagementView roles() {
        List<AdminOperationsDto.RoleDetail> roles = authRoleRepository
                .findAllWithPermissions(Sort.by(Sort.Direction.ASC, "code"))
                .stream()
                .map(this::toRoleDetail)
                .toList();
        List<AdminOperationsDto.PermissionDetail> permissions = authPermissionRepository
                .findAll(Sort.by(Sort.Direction.ASC, "module", "code"))
                .stream()
                .map(this::toPermissionDetail)
                .toList();
        return new AdminOperationsDto.RoleManagementView(roles, permissions);
    }

    @Transactional(rollbackFor = Exception.class)
    public AdminOperationsDto.RoleDetail updateRolePermissions(
            UUID actorUserId,
            String roleCode,
            AdminOperationsDto.UpdateRolePermissionsRequest request
    ) {
        requireFreshAdminActor(actorUserId);
        String normalizedRoleCode = normalizeRoleCode(roleCode);
        if (Roles.SUPER_ADMIN.equals(normalizedRoleCode)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "超级管理员权限由系统权限全集维护");
        }
        AuthRole role = authRoleRepository.findByCode(normalizedRoleCode)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "角色不存在"));
        Set<String> requestedCodes = normalizeCodes(request.permissions());
        Set<AuthPermission> permissions = requestedCodes.isEmpty()
                ? Set.of()
                : authPermissionRepository.findByCodeIn(requestedCodes);
        if (permissions.size() != requestedCodes.size()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "权限编码不存在");
        }
        role.getPermissions().clear();
        role.getPermissions().addAll(permissions);
        authRoleRepository.save(role);
        List<UUID> affectedUserIds = authUserRepository.findAllByRoles_Code(normalizedRoleCode)
                .stream()
                .map(AuthUser::getId)
                .toList();
        userSessionRevocationService.revokeAll(affectedUserIds, "管理员更新角色权限");
        auditLogService.record(actorUserId, "ADMIN_ROLE_PERMISSIONS_UPDATE", "auth_roles", role.getId());
        return toRoleDetail(role);
    }

    public AdminOperationsDto.ConfigManagementView configs() {
        return new AdminOperationsDto.ConfigManagementView(configCenterService.list());
    }

    @Transactional(rollbackFor = Exception.class)
    public ConfigEntryDto updateConfig(UUID actorUserId, String key, AdminOperationsDto.UpdateConfigRequest request) {
        requireFreshAdminActor(actorUserId);
        ConfigEntryDto updated = configCenterService.update(key, request.value(), request.reason(), actorUserId);
        auditLogService.record(actorUserId, "ADMIN_CONFIG_UPDATE", "config_entries", null);
        return updated;
    }

    /**
     * 查询最近任务管理视图。
     *
     * @return 任务管理视图
     */
    @Transactional(readOnly = true)
    public AdminOperationsDto.TaskManagementView tasks() {
        return new AdminOperationsDto.TaskManagementView(
                toTaskRecordItems(taskRecordRepository.findRecent(DEFAULT_TASK_LIMIT))
        );
    }

    private List<AdminOperationsDto.TaskRecordItem> toTaskRecordItems(List<Object[]> rows) {
        return rows.stream().map(row -> new AdminOperationsDto.TaskRecordItem(
                toUuid(row[0]), toText(row[1]), AdminOperationDescription.task(toText(row[1]), toText(row[4])),
                toText(row[2]), toInt(row[3]),
                toText(row[4]), toText(row[5]), toInt(row[6]),
                toInstant(row[7]), toInstant(row[8]),
                toUuidOrNull(row[9]), toText(row[10])
        )).toList();
    }

    @Transactional(rollbackFor = Exception.class)
    public AdminOperationsDto.TaskRecordItem retryTask(UUID actorUserId, UUID taskId) {
        // 先查当前状态验证可重试
        List<Object[]> rows = taskRecordRepository.findByIdRaw(taskId);
        if (rows.isEmpty()) {
            throw new BusinessException(ErrorCode.NOT_FOUND, "任务不存在");
        }
        Object[] row = rows.get(0);
        String currentStatus = row[2] == null ? "" : row[2].toString();
        String routingKey = row[4] == null ? null : row[4].toString();
        if (!RETRYABLE_TASK_STATUS.contains(currentStatus)) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "只有失败、取消或死信任务可以重试");
        }
        if (routingKey == null || routingKey.isBlank()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "任务缺少路由键，无法重新投递");
        }
        Map<String, Object> retryPayload = taskRedispatchService.rebuildPayload(
                taskId,
                toText(row[1]),
                routingKey,
                toText(row[9])
        );
        // 使用 EntityManager RETURNING 获取更新后的完整记录
        AdminOperationsDto.TaskRecordItem retried = metricsRepository.updateTaskStatusReturning(
                taskId,
                TaskStatus.QUEUED.getValue(),
                0
        );
        auditLogService.record(actorUserId, "ADMIN_TASK_RETRY", "sys_tasks", taskId);
        taskRedispatchService.enqueueRedispatch(taskId, routingKey, retryPayload);
        return retried;
    }

    /**
     * 查询最近审计日志管理视图。
     *
     * @return 日志管理视图
     */
    @Transactional(readOnly = true)
    public AdminOperationsDto.LogManagementView logs() {
        return new AdminOperationsDto.LogManagementView(
                toAuditLogItems(auditLogAdminRepository.findAllByOrderByCreatedAtDesc(
                        PageRequest.of(0, DEFAULT_LOG_LIMIT)
                ))
        );
    }

    /**
     * 查询系统监控数据。
     *
     * @return 系统监控视图
     */
    @Transactional(readOnly = true)
    public AdminOperationsDto.MonitoringView monitoring() {
        Instant now = Instant.now();
        SystemSnapshot snapshot = systemSnapshot();
        long runningTasks = taskRecordRepository.countByStatus(TaskStatus.RUNNING.getValue());
        long queuedTasks = taskRecordRepository.countByStatus(TaskStatus.QUEUED.getValue());
        long failedTasks = taskRecordRepository.countByStatus(TaskStatus.FAILED.getValue());
        long dlqTasks = taskRecordRepository.countByStatus(TaskStatus.DLQ.getValue());
        long todayRequests = auditLogAdminRepository.countSince(
                LocalDate.now().atStartOfDay(ZoneId.of("Asia/Shanghai")).toInstant()
        );
        // 队列深度只表示尚未执行的 QUEUED 任务，死信单独展示，避免把历史失败量误报为待处理积压。
        long queueDepth = queuedTasks;
        String queueStatus = failedTasks + dlqTasks > 0 ? "WARN" : "UP";
        String overallStatus = snapshot.diskUsage() >= 90 || snapshot.jvmHeapUsage() >= 90 || "WARN".equals(queueStatus)
                ? "WARN"
                : "UP";

        AdminOperationsDto.MonitoringOverview overview = new AdminOperationsDto.MonitoringOverview(
                overallStatus,
                uptime(),
                snapshot.cpuUsage(),
                snapshot.memoryUsage(),
                snapshot.diskUsage(),
                snapshot.jvmHeapUsage(),
                runningTasks,
                queueDepth,
                todayRequests
        );
        List<AdminConsoleSummaryDto.HealthItem> health = List.of(
                healthItem("数据库", componentStatus("db"), componentDetail("db")),
                healthItem("任务队列", queueStatus, queueDetail(runningTasks, failedTasks, dlqTasks)),
                healthItem("对象存储", componentStatus("minio"), componentDetail("minio")),
                healthItem("病毒防护", componentStatus("clamAv"), componentDetail("clamAv"))
        );
        List<AdminOperationsDto.MonitoringMetric> metrics = List.of(
                new AdminOperationsDto.MonitoringMetric(
                        "系统 CPU", formatPercent(snapshot.cpuUsage()), "%", statusByUsage(snapshot.cpuUsage())
                ),
                new AdminOperationsDto.MonitoringMetric(
                        "系统内存", formatPercent(snapshot.memoryUsage()), "%", statusByUsage(snapshot.memoryUsage())
                ),
                new AdminOperationsDto.MonitoringMetric(
                        "JVM 堆内存", formatPercent(snapshot.jvmHeapUsage()), "%", statusByUsage(snapshot.jvmHeapUsage())
                ),
                new AdminOperationsDto.MonitoringMetric(
                        "磁盘使用率", formatPercent(snapshot.diskUsage()), "%", statusByUsage(snapshot.diskUsage())
                ),
                new AdminOperationsDto.MonitoringMetric("运行中任务", String.valueOf(runningTasks), "count", "UP"),
                new AdminOperationsDto.MonitoringMetric("队列待处理", String.valueOf(queueDepth), "count", queueStatus),
                new AdminOperationsDto.MonitoringMetric("死信任务", String.valueOf(dlqTasks), "count",
                        dlqTasks > 0 ? "WARN" : "UP")
        );
        List<AdminOperationsDto.MonitoringComponent> components = List.of(
                component("PostgreSQL", componentStatus("db"), Map.of(
                        "连接池", "OmniNestHikariPool",
                        "状态", componentDetail("db")
                )),
                component("Redis", componentStatus("redis"), Map.of(
                        "用途", "限流与配置缓存",
                        "状态", componentDetail("redis")
                )),
                component("RabbitMQ", queueStatus, Map.of(
                        "queued", queuedTasks,
                        "running", runningTasks,
                        "failed", failedTasks,
                        "dlq", dlqTasks
                )),
                component("MinIO", componentStatus("minio"), Map.of(
                        "userFilesBucket", objectStorageBuckets.userFiles()
                )),
                component("Lucene Index", "UP", Map.of(
                        "mode", "embedded",
                        "writable", true
                )),
                component("ClamAV", componentStatus("clamAv"), Map.of(
                        "用途", "离线下载导入前病毒扫描",
                        "状态", componentDetail("clamAv")
                )),
                workerComponent()
        );
        List<AdminOperationsDto.MonitoringAlert> alerts = alerts(snapshot, queueDepth, failedTasks + dlqTasks, now);
        List<AdminOperationsDto.AuditLogItem> auditRecent = toAuditLogItems(
                auditLogAdminRepository.findAllByOrderByCreatedAtDesc(PageRequest.of(0, DEFAULT_LOG_LIMIT))
        );
        // 当前没有持久化历史采样，趋势只返回真实的当前值，避免用合成数据误导管理员。
        List<AdminOperationsDto.MonitoringSeries> series = List.of(
                currentOnlySeries("cpu", "CPU 使用率", "%", now, snapshot.cpuUsage()),
                currentOnlySeries("memory", "系统内存使用率", "%", now, snapshot.memoryUsage()),
                currentOnlySeries("jvmHeap", "JVM 堆内存", "%", now, snapshot.jvmHeapUsage()),
                currentOnlySeries("tasks", "任务队列深度", "count", now, queueDepth)
        );
        return new AdminOperationsDto.MonitoringView(
                overview,
                components,
                alerts,
                auditRecent,
                series,
                health,
                metrics
        );
    }

    /**
     * 查询存储管理视图。
     *
     * @return 存储管理视图
     */
    @Transactional(readOnly = true)
    public AdminOperationsDto.StorageManagementView storage() {
        return new AdminOperationsDto.StorageManagementView(bucketItems());
    }

    private AdminOperationsDto.RuntimeCapabilityItem aggregateRuntimeCapability(
            List<WorkerRuntimeState> states,
            String capabilityName
    ) {
        if (states.isEmpty()) {
            return new AdminOperationsDto.RuntimeCapabilityItem(
                    "UNKNOWN",
                    "未检测到活动 Worker",
                    null,
                    null
            );
        }
        WorkerRuntimeState selected = states.getFirst();
        for (WorkerRuntimeState candidate : states) {
            if (isBetterCapabilityCandidate(candidate, selected, capabilityName)) {
                selected = candidate;
            }
        }
        return runtimeCapability(selected, capabilityName);
    }

    private boolean isBetterCapabilityCandidate(
            WorkerRuntimeState candidate,
            WorkerRuntimeState current,
            String capabilityName
    ) {
        int candidatePriority = capabilityPriority(candidate.capability(capabilityName));
        int currentPriority = capabilityPriority(current.capability(capabilityName));
        if (candidatePriority != currentPriority) {
            return candidatePriority > currentPriority;
        }
        return candidate.reportedAt().isAfter(current.reportedAt());
    }

    private int capabilityPriority(WorkerRuntimeState.CapabilityStatus capability) {
        return switch (capability.status()) {
            case "UP" -> 4;
            case "DOWN" -> 3;
            case "DISABLED" -> 2;
            case "UNKNOWN" -> 1;
            default -> 0;
        };
    }

    private AdminOperationsDto.RuntimeCapabilityItem runtimeCapability(
            WorkerRuntimeState state,
            String capabilityName
    ) {
        WorkerRuntimeState.CapabilityStatus capability = state.capability(capabilityName);
        return new AdminOperationsDto.RuntimeCapabilityItem(
                capability.status(),
                capability.detail(),
                state.reportedAt(),
                state.instanceId()
        );
    }

    private AdminOperationsDto.MonitoringComponent workerComponent() {
        List<WorkerRuntimeState> states = workerRuntimeRegistry.activeInstances();
        if (states.isEmpty()) {
            return component("Worker", "DOWN", Map.of("状态", "未检测到活动 Worker"));
        }
        Map<String, Object> detail = new LinkedHashMap<>();
        detail.put("activeInstanceCount", states.size());
        detail.put("photoAi", aggregateRuntimeCapability(states, WorkerRuntimeState.PHOTO_AI_CAPABILITY));
        detail.put("instances", states.stream().map(this::workerInstanceDetail).toList());
        return component("Worker", "UP", detail);
    }

    private Map<String, Object> workerInstanceDetail(WorkerRuntimeState state) {
        Map<String, Object> detail = new LinkedHashMap<>();
        detail.put("instanceId", state.instanceId());
        detail.put("reportedAt", state.reportedAt());
        detail.put("capabilities", state.capabilities());
        return detail;
    }

    @Transactional(readOnly = true)
    public AdminOperationsDto.ExternalStorageView externalStorage() {
        return new AdminOperationsDto.ExternalStorageView(
                toExternalStorageItems(externalStorageAdministration.listAccounts())
        );
    }

    private List<AdminOperationsDto.ExternalStorageItem> toExternalStorageItems(
            List<ExternalStorageAccountSummary> accounts
    ) {
        return accounts.stream()
                .map(this::toExternalStorageItem)
                .toList();
    }

    private AdminOperationsDto.ExternalStorageItem toExternalStorageItem(ExternalStorageAccountSummary account) {
        return new AdminOperationsDto.ExternalStorageItem(
                account.id(),
                account.provider(),
                account.displayName(),
                account.status(),
                account.createdAt(),
                account.updatedAt()
        );
    }

    @Transactional(rollbackFor = Exception.class)
    public AdminOperationsDto.ExternalStorageItem updateExternalStorageStatus(
            UUID actorUserId,
            UUID id,
            AdminOperationsDto.UpdateExternalStorageStatusRequest request
    ) {
        String status = normalizeText(request.status(), "外部存储状态不能为空").toUpperCase(Locale.ROOT);
        AdminOperationsDto.ExternalStorageItem storage = toExternalStorageItem(
                externalStorageAdministration.updateStatus(id, status)
        );
        auditLogService.record(actorUserId, "ADMIN_EXTERNAL_STORAGE_STATUS_UPDATE", "storage_external_accounts", id);
        return storage;
    }

    private List<AdminOperationsDto.BucketItem> bucketItems() {
        return List.of(
                new AdminOperationsDto.BucketItem(objectStorageBuckets.userFiles(), "用户文件", "CONFIGURED"),
                new AdminOperationsDto.BucketItem(objectStorageBuckets.derivedAssets(), "衍生资源", "CONFIGURED")
        );
    }

    private AdminOperationsDto.RoleDetail toRoleDetail(AuthRole role) {
        List<String> permissions = role.getPermissions().stream()
                .filter(AuthPermission::isEnabled)
                .map(AuthPermission::getCode)
                .sorted()
                .toList();
        return new AdminOperationsDto.RoleDetail(
                role.getCode(),
                role.getName(),
                role.getDescription(),
                role.isBuiltIn(),
                role.isEnabled(),
                permissions
        );
    }

    private AdminOperationsDto.PermissionDetail toPermissionDetail(AuthPermission permission) {
        return new AdminOperationsDto.PermissionDetail(
                permission.getCode(),
                permission.getName(),
                permission.getModule(),
                permission.getDescription(),
                permission.isEnabled()
        );
    }

    private void requireFreshAdminActor(UUID actorUserId) {
        AuthUser actor = authUserRepository.findWithRolesAndPermissionsById(actorUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.UNAUTHORIZED, "操作者不存在"));
        if (!UserStatus.ACTIVE.getValue().equals(actor.getStatus())) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "操作者不可用");
        }
        boolean privileged = actor.getRoles().stream()
                .map(AuthRole::getCode)
                .anyMatch(code -> Roles.SUPER_ADMIN.equals(code) || Roles.ADMIN.equals(code));
        if (!privileged) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "操作者已失去管理权限");
        }
    }

    private Set<String> normalizeCodes(Set<String> rawCodes) {
        if (rawCodes == null || rawCodes.isEmpty()) {
            return Set.of();
        }
        return rawCodes.stream()
                .map(code -> code == null ? "" : code.trim())
                .filter(code -> !code.isEmpty())
                .sorted(Comparator.naturalOrder())
                .collect(Collectors.toCollection(LinkedHashSet::new));
    }

    private String normalizeRoleCode(String roleCode) {
        String normalized = roleCode == null ? "" : roleCode.trim().toUpperCase(Locale.ROOT);
        if (normalized.isEmpty()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "角色编码不能为空");
        }
        return normalized;
    }

    private String normalizeText(String value, String errorMessage) {
        String normalized = value == null ? "" : value.trim();
        if (normalized.isEmpty()) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, errorMessage);
        }
        return normalized;
    }

    private AdminConsoleSummaryDto.HealthItem healthItem(String name, String status, String detail) {
        return new AdminConsoleSummaryDto.HealthItem(name, status, detail);
    }

    private String queueDetail(long running, long failed, long dlq) {
        return "运行中 " + running + "，失败 " + failed + "，死信 " + dlq + "。";
    }

    private AdminOperationsDto.MonitoringComponent component(
            String name,
            String status,
            Map<String, Object> detail
    ) {
        return new AdminOperationsDto.MonitoringComponent(name, status, detail);
    }

    private List<AdminOperationsDto.MonitoringAlert> alerts(
            SystemSnapshot snapshot,
            long queueDepth,
            long failedTasks,
            Instant now
    ) {
        ArrayList<AdminOperationsDto.MonitoringAlert> alerts = new ArrayList<>();
        if (snapshot.cpuUsage() >= 80) {
            alerts.add(new AdminOperationsDto.MonitoringAlert("WARNING", "系统 CPU 使用率偏高", now));
        }
        if (snapshot.diskUsage() >= 85) {
            alerts.add(new AdminOperationsDto.MonitoringAlert("WARNING", "磁盘使用率超过 85%", now));
        }
        if (snapshot.jvmHeapUsage() >= 85) {
            alerts.add(new AdminOperationsDto.MonitoringAlert("WARNING", "JVM 堆内存使用率偏高", now));
        }
        if (queueDepth > 0) {
            alerts.add(new AdminOperationsDto.MonitoringAlert("INFO", "后台队列存在待处理任务：" + queueDepth, now));
        }
        if (failedTasks > 0) {
            alerts.add(new AdminOperationsDto.MonitoringAlert("WARNING", "存在失败或死信任务：" + failedTasks, now));
        }
        if (alerts.isEmpty()) {
            alerts.add(new AdminOperationsDto.MonitoringAlert("INFO", "当前没有需要处理的系统告警", now));
        }
        return alerts.stream().limit(10).toList();
    }

    private AdminOperationsDto.MonitoringSeries currentOnlySeries(
            String metric, String label, String unit, Instant now, double current
    ) {
        return new AdminOperationsDto.MonitoringSeries(
                metric, label, unit,
                List.of(new AdminOperationsDto.MonitoringSeriesPoint(now, current))
        );
    }

    /**
     * 通过 Actuator 获取组件健康状态。
     */
    private String componentStatus(String componentName) {
        try {
            var health = healthEndpoint.healthForPath(componentName);
            if (health == null) {
                return "DOWN";
            }
            return Status.UP.equals(health.getStatus()) ? "UP" : "WARN";
        } catch (Exception e) {
            return "DOWN";
        }
    }

    /**
     * 通过 Actuator 获取组件健康详情。
     */
    private String componentDetail(String componentName) {
        try {
            var health = healthEndpoint.healthForPath(componentName);
            if (health == null) {
                return "不可用";
            }
            return health.getStatus().getCode();
        } catch (Exception e) {
            return "不可用";
        }
    }

    private String uptime() {
        long uptimeMillis = ManagementFactory.getRuntimeMXBean().getUptime();
        long days = uptimeMillis / 86_400_000;
        long hours = (uptimeMillis % 86_400_000) / 3_600_000;
        long minutes = (uptimeMillis % 3_600_000) / 60_000;
        return days + "d " + hours + "h " + minutes + "m";
    }

    private SystemSnapshot systemSnapshot() {
        Runtime runtime = Runtime.getRuntime();
        MemoryMXBean memoryMXBean = ManagementFactory.getMemoryMXBean();
        MemoryUsage heap = memoryMXBean.getHeapMemoryUsage();
        double cpuUsage = cpuUsage();
        double memoryUsage = ratio(runtime.totalMemory() - runtime.freeMemory(), runtime.maxMemory());
        double heapUsage = ratio(heap.getUsed(), heap.getMax());
        File disk = new File(".");
        double diskUsage = ratio(disk.getTotalSpace() - disk.getFreeSpace(), disk.getTotalSpace());
        return new SystemSnapshot(cpuUsage, memoryUsage, diskUsage, heapUsage);
    }

    private double cpuUsage() {
        var bean = ManagementFactory.getOperatingSystemMXBean();
        if (bean instanceof OperatingSystemMXBean operatingSystemMXBean) {
            return round(Math.max(0, operatingSystemMXBean.getCpuLoad()) * 100);
        }
        double load = bean.getSystemLoadAverage();
        int processors = Math.max(1, bean.getAvailableProcessors());
        return round(Math.max(0, load) / processors * 100);
    }

    private double ratio(long used, long total) {
        if (total <= 0) {
            return 0;
        }
        return round((double) used * 100 / total);
    }

    private double round(double value) {
        return Math.round(value * 10.0) / 10.0;
    }

    private String formatPercent(double value) {
        return String.format(Locale.ROOT, "%.1f", value);
    }

    private String statusByUsage(double value) {
        return value >= 85 ? "WARN" : "UP";
    }

    private record SystemSnapshot(
            double cpuUsage,
            double memoryUsage,
            double diskUsage,
            double jvmHeapUsage
    ) {
    }

    // ── 会话管理 ──────────────────────────────────────────────────────────

    /**
     * 查询最近的系统会话。
     *
     * @return 会话管理视图
     */
    @Transactional(readOnly = true)
    public AdminOperationsDto.SessionManagementView allSessions() {
        List<AuthActiveSession> sessions = activeSessionRepository.findAllByOrderByCreatedAtDesc(
                PageRequest.of(0, DEFAULT_SESSION_LIMIT)
        );
        return new AdminOperationsDto.SessionManagementView(toSessionItems(sessions));
    }

    private List<AdminOperationsDto.SessionItem> toSessionItems(List<AuthActiveSession> sessions) {
        // 批量查询用户名，避免 N+1。
        Set<UUID> userIds = sessions.stream()
                .map(AuthActiveSession::getUserId)
                .collect(Collectors.toSet());
        Map<UUID, String> usernameMap = userIds.isEmpty()
                ? Map.of()
                : authUserRepository.findAllById(userIds).stream()
                    .collect(Collectors.toMap(
                            AuthUser::getId,
                            u -> u.getUsername() != null ? u.getUsername() : ""));

        return sessions.stream()
                .map(s -> new AdminOperationsDto.SessionItem(
                        s.getId(), s.getUserId(), usernameMap.getOrDefault(s.getUserId(), ""),
                        s.getClientPlatform(), s.getDeviceId(), s.getDeviceName(),
                        s.getIpAddress(), s.getIssuedAt(), s.getExpiresAt(), s.getLastActiveAt(),
                        s.getRevokedAt(), s.getRevokeReason()))
                .toList();
    }

    @Transactional(rollbackFor = Exception.class)
    public void revokeSession(UUID actorUserId, UUID sessionId) {
        var session = activeSessionRepository.findById(sessionId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "会话不存在"));
        sessionRevocationService.revokeSession(session.getUserId(), sessionId, Duration.ofDays(30));
        activeSessionRepository.revokeBySessionId(sessionId, "管理员强制撤销");
        auditLogService.record(actorUserId, "ADMIN_SESSION_REVOKE", "auth_active_sessions", sessionId);
    }

    /**
     * 清理指定保留天数之外的操作审计日志。
     *
     * @param actorUserId 操作者用户标识
     * @param retentionDays 保留天数
     * @return 删除数量
     */
    @Transactional(rollbackFor = Exception.class)
    public int cleanupAuditLogs(UUID actorUserId, int retentionDays) {
        Instant cutoff = cleanupCutoff(retentionDays);
        int deleted = auditLogAdminRepository.deleteCreatedBefore(cutoff);
        auditLogService.recordWithMetadata(
                actorUserId,
                "ADMIN_AUDIT_LOG_CLEANUP",
                "audit_logs",
                null,
                Map.of("retentionDays", retentionDays, "deletedCount", deleted)
        );
        return deleted;
    }

    /**
     * 清理指定保留天数之外的登录审计日志。
     *
     * @param actorUserId 操作者用户标识
     * @param retentionDays 保留天数
     * @return 删除数量
     */
    @Transactional(rollbackFor = Exception.class)
    public int cleanupLoginAuditLogs(UUID actorUserId, int retentionDays) {
        int deleted = loginAuditRepository.deleteCreatedBefore(cleanupCutoff(retentionDays));
        auditLogService.recordWithMetadata(
                actorUserId,
                "ADMIN_LOGIN_AUDIT_CLEANUP",
                "auth_login_audits",
                null,
                Map.of("retentionDays", retentionDays, "deletedCount", deleted)
        );
        return deleted;
    }

    /**
     * 清理指定保留天数之外的过期或已撤销会话。
     *
     * @param actorUserId 操作者用户标识
     * @param retentionDays 保留天数
     * @return 删除数量
     */
    @Transactional(rollbackFor = Exception.class)
    public int cleanupSessions(UUID actorUserId, int retentionDays) {
        int deleted = activeSessionRepository.deleteInactiveBefore(cleanupCutoff(retentionDays));
        auditLogService.recordWithMetadata(
                actorUserId,
                "ADMIN_SESSION_CLEANUP",
                "auth_active_sessions",
                null,
                Map.of("retentionDays", retentionDays, "deletedCount", deleted)
        );
        return deleted;
    }

    private Instant cleanupCutoff(int retentionDays) {
        if (retentionDays < 0 || retentionDays > 3650) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "保留天数必须在 0 到 3650 之间");
        }
        return Instant.now().minus(Duration.ofDays(retentionDays));
    }

    // ── 登录日志 ──────────────────────────────────────────────────────────

    /**
     * 查询最近的登录审计记录。
     *
     * @return 登录审计视图
     */
    @Transactional(readOnly = true)
    public AdminOperationsDto.LoginAuditView loginAuditLogs() {
        return new AdminOperationsDto.LoginAuditView(toLoginAuditItems(
                loginAuditRepository.findAllByOrderByCreatedAtDesc(
                        PageRequest.of(0, DEFAULT_LOGIN_AUDIT_LIMIT)
                )
        ));
    }

    // ── 实体 → DTO 映射 ──────────────────────────────────────────────────

    private List<AdminOperationsDto.AuditLogItem> toAuditLogItems(List<AuditLog> logs) {
        return logs.stream().map(a -> new AdminOperationsDto.AuditLogItem(
                a.getId(), a.getActorUserId(), a.getAction(),
                AdminOperationDescription.audit(a.getAction(), a.getResourceType()),
                a.getResourceType(), a.getResourceId(),
                a.getIpAddress(), a.getCreatedAt()
        )).toList();
    }

    private List<AdminOperationsDto.LoginAuditItem> toLoginAuditItems(List<AuthLoginAudit> audits) {
        return audits.stream().map(audit -> new AdminOperationsDto.LoginAuditItem(
                audit.getId(), audit.getUserId(), audit.getUsername(), audit.getLoginResult(),
                audit.getClientPlatform(), audit.getIpAddress(), audit.getUserAgent(),
                audit.getFailureReason(), audit.getCreatedAt()
        )).toList();
    }

    private UUID toUuid(Object value) {
        if (value instanceof UUID uuid) return uuid;
        return UUID.fromString(value.toString());
    }

    /**
     * 系统任务的归属用户可以为空，投影转换不得因此中断整页数据。
     */
    private UUID toUuidOrNull(Object value) {
        if (value == null) {
            return null;
        }
        return toUuid(value);
    }

    private String toText(Object value) {
        return value == null ? null : value.toString();
    }

    private int toInt(Object value) {
        if (value instanceof Number n) return n.intValue();
        return Integer.parseInt(value.toString());
    }

    private Instant toInstant(Object value) {
        if (value instanceof Instant i) return i;
        if (value instanceof Timestamp t) return t.toInstant();
        return Instant.parse(value.toString());
    }
}
