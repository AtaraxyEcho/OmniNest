package com.omninest.modules.user.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;

/**
 * 管理后台仪表盘分析数据，包含时间序列指标与系统负载快照。
 */
@Schema(description = "管理后台分析数据")
public record AdminAnalyticsDto(
        @Schema(description = "用户增长趋势") List<DailyMetric> userGrowth,
        @Schema(description = "任务吞吐量趋势") List<DailyTaskMetric> taskThroughput,
        @Schema(description = "存储增长趋势") List<DailyMetric> storageGrowth,
        @Schema(description = "当前系统负载快照") SystemLoadSnapshot currentLoad
) {
    /** 每日单值指标（日期 + 数值）。 */
    @Schema(description = "每日单值指标")
    public record DailyMetric(
            @Schema(description = "日期", example = "2026-06-07") String date,
            @Schema(description = "数值", example = "100") long value
    ) {}

    /** 每日任务状态分布（已完成 / 失败 / 运行中）。 */
    @Schema(description = "每日任务状态分布")
    public record DailyTaskMetric(
            @Schema(description = "日期", example = "2026-06-07") String date,
            @Schema(description = "已完成数", example = "50") long completed,
            @Schema(description = "失败数", example = "2") long failed,
            @Schema(description = "运行中数", example = "5") long running
    ) {}

    /** 系统负载快照（CPU、内存、磁盘、JVM 堆使用率，单位百分比）。 */
    @Schema(description = "系统负载快照")
    public record SystemLoadSnapshot(
            @Schema(description = "CPU 使用率", example = "45.2") double cpuUsage,
            @Schema(description = "内存使用率", example = "62.5") double memoryUsage,
            @Schema(description = "磁盘使用率", example = "38.7") double diskUsage,
            @Schema(description = "JVM 堆使用率", example = "55.3") double jvmHeapUsage
    ) {}
}
