package com.omninest.modules.user.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;
import java.util.Map;

@Schema(description = "管理后台仪表盘摘要")
public record AdminConsoleSummaryDto(
        @Schema(description = "用户统计") UserStats users,
        @Schema(description = "角色列表") List<RoleSummary> roles,
        @Schema(description = "配置统计") ConfigStats configs,
        @Schema(description = "任务统计") TaskStats tasks,
        @Schema(description = "存储统计") StorageStats storage,
        @Schema(description = "健康检查项") List<HealthItem> health
) {
    @Schema(description = "用户统计")
    public record UserStats(
            @Schema(description = "用户总数", example = "100") long total,
            @Schema(description = "活跃用户数", example = "85") long active,
            @Schema(description = "禁用用户数", example = "15") long disabled,
            @Schema(description = "各角色用户数") Map<String, Long> roleCounts
    ) {
    }

    @Schema(description = "角色摘要")
    public record RoleSummary(
            @Schema(description = "角色编码", example = "ADMIN") String code,
            @Schema(description = "角色名称", example = "管理员") String name,
            @Schema(description = "角色描述") String description,
            @Schema(description = "是否内置角色", example = "true") boolean builtIn,
            @Schema(description = "是否启用", example = "true") boolean enabled,
            @Schema(description = "权限数量", example = "9") long permissionCount,
            @Schema(description = "权限编码列表") List<String> permissions
    ) {
    }

    @Schema(description = "配置统计")
    public record ConfigStats(
            @Schema(description = "配置总数", example = "50") long total,
            @Schema(description = "热更新配置数", example = "10") long hot,
            @Schema(description = "下次任务更新数", example = "5") long nextTask,
            @Schema(description = "需重启配置数", example = "2") long restartRequired
    ) {
    }

    @Schema(description = "任务统计")
    public record TaskStats(
            @Schema(description = "任务总数", example = "1000") long total,
            @Schema(description = "排队中任务数", example = "10") long queued,
            @Schema(description = "运行中任务数", example = "5") long running,
            @Schema(description = "已完成任务数", example = "950") long completed,
            @Schema(description = "失败任务数", example = "20") long failed,
            @Schema(description = "已取消任务数", example = "10") long cancelled,
            @Schema(description = "死信队列任务数", example = "5") long dlq
    ) {
    }

    @Schema(description = "存储统计")
    public record StorageStats(
            @Schema(description = "文件数量", example = "5000") long fileCount,
            @Schema(description = "文件夹数量", example = "200") long folderCount,
            @Schema(description = "对象数量", example = "5200") long objectCount,
            @Schema(description = "已用存储（字节）", example = "10737418240") long usedBytes,
            @Schema(description = "外部存储账户数", example = "2") long externalAccountCount
    ) {
    }

    @Schema(description = "健康检查项")
    public record HealthItem(
            @Schema(description = "组件名称", example = "PostgreSQL") String name,
            @Schema(description = "状态", example = "UP") String status,
            @Schema(description = "详细信息") String detail
    ) {
    }
}
