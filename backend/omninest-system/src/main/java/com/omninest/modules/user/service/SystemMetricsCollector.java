package com.omninest.modules.user.service;

import com.sun.management.OperatingSystemMXBean;
import java.io.File;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import org.springframework.stereotype.Component;

/**
 * 后台监控快照的唯一采集口径。
 *
 * <p>分析页与运维页曾各写一份算法：一处用 {@code totalMemory} 当分母并把 JVM 堆
 * 当作系统内存展示，另一处用 {@code maxMemory}；磁盘一处按 {@code /}、另一处按 {@code .}。
 * 同一字段名给出两个数，管理员无法据此判断容量。两个面板因此共用本组件。</p>
 *
 * @author OmniNest
 */
@Component
public class SystemMetricsCollector {

    /**
     * 采集 CPU、堆内存、磁盘与容器可用内存使用率，均为百分比且保留一位小数。
     *
     * @return 四项使用率
     */
    public Snapshot collect() {
        MemoryMXBean memoryMXBean = ManagementFactory.getMemoryMXBean();
        var heap = memoryMXBean.getHeapMemoryUsage();
        File disk = new File(System.getProperty("user.dir", "/"));
        long totalSpace = disk.getTotalSpace();
        long totalSystemMemory = 0;
        long freeSystemMemory = 0;
        if (ManagementFactory.getOperatingSystemMXBean() instanceof OperatingSystemMXBean operatingSystem) {
            totalSystemMemory = operatingSystem.getTotalMemorySize();
            freeSystemMemory = operatingSystem.getFreeMemorySize();
        }
        return new Snapshot(
                round(Math.max(0, cpuLoad()) * 100),
                ratio(heap.getUsed(), heap.getMax()),
                ratio(totalSpace - disk.getFreeSpace(), totalSpace),
                ratio(totalSystemMemory - freeSystemMemory, totalSystemMemory)
        );
    }

    /**
     * CPU 使用率（0~1）。JVM 不提供即时 CPU 占比时退回系统平均负载。
     */
    private double cpuLoad() {
        var bean = ManagementFactory.getOperatingSystemMXBean();
        if (bean instanceof OperatingSystemMXBean operatingSystemMXBean) {
            double load = operatingSystemMXBean.getCpuLoad();
            if (load >= 0) {
                return load;
            }
        }
        double loadAverage = bean.getSystemLoadAverage();
        if (loadAverage < 0) {
            return 0;
        }
        return loadAverage / Math.max(1, bean.getAvailableProcessors());
    }

    private double ratio(long used, long total) {
        if (total <= 0) {
            return 0;
        }
        return round(Math.max(0, (double) used * 100 / total));
    }

    private double round(double value) {
        return Math.round(value * 10.0) / 10.0;
    }

    /**
     * 一次采集的结果。
     *
     * @param cpuUsagePercent CPU 使用率
     * @param heapUsagePercent JVM 堆使用率（以最大堆为分母）
     * @param diskUsagePercent 进程工作目录所在卷的磁盘使用率
     * @param systemMemoryUsagePercent 宿主机/容器物理内存使用率
     */
    public record Snapshot(
            double cpuUsagePercent,
            double heapUsagePercent,
            double diskUsagePercent,
            double systemMemoryUsagePercent
    ) {
    }
}
