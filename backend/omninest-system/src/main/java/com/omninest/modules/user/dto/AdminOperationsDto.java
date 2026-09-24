package com.omninest.modules.user.dto;

import com.omninest.modules.configcenter.dto.ConfigEntryDto;
import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * 汇总管理后台操作相关的数据传输对象。
 *
 * @author OmniNest
 */
@Schema(description = "管理后台操作相关 DTO 集合")
public final class AdminOperationsDto {
    private AdminOperationsDto() {
    }

    @Schema(description = "权限详情")
    public record PermissionDetail(
            @Schema(description = "权限编码", example = "FILE_READ") String code,
            @Schema(description = "权限名称", example = "文件读取") String name,
            @Schema(description = "所属模块", example = "storage") String module,
            @Schema(description = "权限描述") String description,
            @Schema(description = "是否启用", example = "true") boolean enabled
    ) {
    }

    @Schema(description = "角色详情")
    public record RoleDetail(
            @Schema(description = "角色编码", example = "ADMIN") String code,
            @Schema(description = "角色名称", example = "管理员") String name,
            @Schema(description = "角色描述") String description,
            @Schema(description = "是否内置角色", example = "true") boolean builtIn,
            @Schema(description = "是否启用", example = "true") boolean enabled,
            @Schema(description = "权限编码列表") List<String> permissions
    ) {
    }

    @Schema(description = "角色管理视图")
    public record RoleManagementView(
            @Schema(description = "角色列表") List<RoleDetail> roles,
            @Schema(description = "权限列表") List<PermissionDetail> permissions
    ) {
    }

    @Schema(description = "更新角色权限请求")
    public record UpdateRolePermissionsRequest(
            @Schema(description = "权限编码集合") Set<String> permissions
    ) {
    }

    @Schema(description = "管理员更新用户角色请求")
    public record UpdateUserRolesRequest(
            @Schema(description = "角色编码集合") Set<String> roles
    ) {
    }

    @Schema(description = "更新配置请求")
    public record UpdateConfigRequest(
            @Schema(description = "配置值", example = "newValue") @NotNull @Size(max = 8192) String value,
            @Schema(description = "变更原因") @Size(max = 500) String reason
    ) {
    }

    @Schema(description = "配置管理视图")
    public record ConfigManagementView(
            @Schema(description = "配置项列表") List<ConfigEntryDto> items
    ) {
    }

    /**
     * 任务记录项。
     *
     * <p>{@link #ownerUserId} 与 {@link #ownerLabel} 用于管理端把失败任务归到人：
     * 任务不再是普通用户可见概念后，管理员是唯一能发现并重试失败的人。
     * 无归属用户的系统任务两项为空。</p>
     */
    @Schema(description = "任务记录项")
    public record TaskRecordItem(
            @Schema(description = "任务 ID") UUID id,
            @Schema(description = "任务类型", example = "FILE_INDEX") String taskType,
            @Schema(description = "任务内容描述") String description,
            @Schema(description = "任务状态", example = "COMPLETED") String status,
            @Schema(description = "进度百分比", example = "100") int progress,
            @Schema(description = "路由键") String routingKey,
            @Schema(description = "错误摘要") String errorSummary,
            @Schema(description = "重试次数", example = "0") int retryCount,
            @Schema(description = "创建时间") Instant createdAt,
            @Schema(description = "更新时间") Instant updatedAt,
            @Schema(description = "归属用户 ID，系统任务为空") UUID ownerUserId,
            @Schema(description = "归属用户显示名，优先昵称回退账号名", example = "ataraxy") String ownerLabel
    ) {
    }

    @Schema(description = "任务管理视图")
    public record TaskManagementView(
            @Schema(description = "任务列表") List<TaskRecordItem> items
    ) {
    }

    @Schema(description = "审计日志项")
    public record AuditLogItem(
            @Schema(description = "日志 ID") UUID id,
            @Schema(description = "操作者用户 ID") UUID actorUserId,
            @Schema(description = "操作类型", example = "USER_CREATE") String action,
            @Schema(description = "操作内容描述") String description,
            @Schema(description = "资源类型", example = "USER") String resourceType,
            @Schema(description = "资源 ID") UUID resourceId,
            @Schema(description = "IP 地址", example = "192.168.1.1") String ipAddress,
            @Schema(description = "创建时间") Instant createdAt
    ) {
    }

    @Schema(description = "日志管理视图")
    public record LogManagementView(
            @Schema(description = "日志列表") List<AuditLogItem> items
    ) {
    }

    @Schema(description = "监控指标")
    public record MonitoringMetric(
            @Schema(description = "指标名称", example = "cpu_usage") String name,
            @Schema(description = "指标值", example = "45.2") String value,
            @Schema(description = "单位", example = "%") String unit,
            @Schema(description = "状态", example = "NORMAL") String status
    ) {
    }

    @Schema(description = "监控概览")
    public record MonitoringOverview(
            @Schema(description = "整体状态", example = "HEALTHY") String status,
            @Schema(description = "运行时长", example = "3d 12h") String uptime,
            @Schema(description = "CPU 使用率", example = "45.2") double cpuUsage,
            @Schema(description = "内存使用率", example = "62.5") double memoryUsage,
            @Schema(description = "磁盘使用率", example = "38.7") double diskUsage,
            @Schema(description = "JVM 堆使用率", example = "55.3") double jvmHeapUsage,
            @Schema(description = "活跃任务数", example = "5") long activeTasks,
            @Schema(description = "队列深度", example = "10") long queueDepth,
            @Schema(description = "今日请求数", example = "12345") long todayRequests
    ) {
    }

    @Schema(description = "监控组件")
    public record MonitoringComponent(
            @Schema(description = "组件名称", example = "PostgreSQL") String name,
            @Schema(description = "组件状态", example = "UP") String status,
            @Schema(description = "组件详情") Map<String, Object> detail
    ) {
    }

    @Schema(description = "监控告警")
    public record MonitoringAlert(
            @Schema(description = "告警级别", example = "WARNING") String severity,
            @Schema(description = "告警消息") String message,
            @Schema(description = "告警时间") Instant timestamp
    ) {
    }

    @Schema(description = "监控时间序列数据点")
    public record MonitoringSeriesPoint(
            @Schema(description = "时间戳") Instant timestamp,
            @Schema(description = "数值", example = "45.2") double value
    ) {
    }

    @Schema(description = "监控时间序列")
    public record MonitoringSeries(
            @Schema(description = "指标名称", example = "cpu_usage") String metric,
            @Schema(description = "标签", example = "系统 CPU") String label,
            @Schema(description = "单位", example = "%") String unit,
            @Schema(description = "数据点列表") List<MonitoringSeriesPoint> points
    ) {
    }

    @Schema(description = "监控视图")
    public record MonitoringView(
            @Schema(description = "监控概览") MonitoringOverview overview,
            @Schema(description = "监控组件列表") List<MonitoringComponent> components,
            @Schema(description = "告警列表") List<MonitoringAlert> alerts,
            @Schema(description = "最近审计日志") List<AuditLogItem> auditRecent,
            @Schema(description = "时间序列数据") List<MonitoringSeries> series,
            @Schema(description = "健康检查项") List<AdminConsoleSummaryDto.HealthItem> health,
            @Schema(description = "指标列表") List<MonitoringMetric> metrics
    ) {
    }

    @Schema(description = "存储桶信息")
    public record BucketItem(
            @Schema(description = "桶名称", example = "omninest-files") String name,
            @Schema(description = "用途", example = "用户文件存储") String purpose,
            @Schema(description = "状态", example = "ACTIVE") String status
    ) {
    }

    @Schema(description = "运行时能力状态")
    public record RuntimeCapabilityItem(
            @Schema(description = "状态", example = "UP") String status,
            @Schema(description = "状态说明") String detail,
            @Schema(description = "Worker 上报时间") Instant observedAt,
            @Schema(description = "Worker 实例标识") String workerInstanceId
    ) {
    }

    @Schema(description = "存储管理视图")
    public record StorageManagementView(
            @Schema(description = "存储桶列表") List<BucketItem> buckets
    ) {
    }

    @Schema(description = "外部存储账户信息")
    public record ExternalStorageItem(
            @Schema(description = "账户 ID") UUID id,
            @Schema(description = "存储提供者", example = "RCLONE") String provider,
            @Schema(description = "显示名称", example = "我的网盘") String displayName,
            @Schema(description = "状态", example = "ACTIVE") String status,
            @Schema(description = "创建时间") Instant createdAt,
            @Schema(description = "更新时间") Instant updatedAt
    ) {
    }

    @Schema(description = "外部存储视图")
    public record ExternalStorageView(
            @Schema(description = "外部存储列表") List<ExternalStorageItem> items
    ) {
    }

    @Schema(description = "创建外部存储请求")
    public record CreateExternalStorageRequest(
            @Schema(description = "存储提供者", example = "RCLONE") @NotBlank String provider,
            @Schema(description = "显示名称", example = "我的网盘") @NotBlank String displayName,
            @Schema(description = "加密凭据") String credentials
    ) {
    }

    @Schema(description = "更新外部存储状态请求")
    public record UpdateExternalStorageStatusRequest(
            @Schema(description = "状态", example = "ACTIVE") @NotBlank String status
    ) {
    }

    // 会话管理
    @Schema(description = "会话信息")
    public record SessionItem(
            @Schema(description = "会话 ID") UUID id,
            @Schema(description = "用户 ID") UUID userId,
            @Schema(description = "用户名", example = "admin") String username,
            @Schema(description = "客户端平台", example = "web") String clientPlatform,
            @Schema(description = "设备 ID") String deviceId,
            @Schema(description = "设备名称", example = "Chrome 浏览器") String deviceName,
            @Schema(description = "IP 地址", example = "192.168.1.1") String ipAddress,
            @Schema(description = "签发时间") Instant issuedAt,
            @Schema(description = "过期时间") Instant expiresAt,
            @Schema(description = "最后活跃时间") Instant lastActiveAt,
            @Schema(description = "吊销时间") Instant revokedAt,
            @Schema(description = "吊销原因") String revokeReason
    ) {
    }

    @Schema(description = "会话管理视图")
    public record SessionManagementView(
            @Schema(description = "会话列表") List<SessionItem> items
    ) {
    }

    // 登录日志
    @Schema(description = "登录审计日志项")
    public record LoginAuditItem(
            @Schema(description = "日志 ID") UUID id,
            @Schema(description = "用户 ID") UUID userId,
            @Schema(description = "用户名", example = "admin") String username,
            @Schema(description = "登录结果", example = "SUCCESS") String loginResult,
            @Schema(description = "客户端平台", example = "web") String clientPlatform,
            @Schema(description = "IP 地址", example = "192.168.1.1") String ipAddress,
            @Schema(description = "用户代理") String userAgent,
            @Schema(description = "失败原因") String failureReason,
            @Schema(description = "创建时间") Instant createdAt
    ) {
    }

    @Schema(description = "登录审计视图")
    public record LoginAuditView(
            @Schema(description = "登录日志列表") List<LoginAuditItem> items
    ) {
    }
}
