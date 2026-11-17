package com.omninest.worker.photos;

import com.omninest.common.concurrency.DistributedLock;
import com.omninest.modules.photos.service.GeoDatasetService;
import com.omninest.modules.photos.service.GeonamesImportService;
import com.omninest.modules.photos.service.PhotosRuntimeConfigService;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.stereotype.Component;

/**
 * GeoNames 数据集自动导入触发器。
 *
 * <p>应用启动时，若当前没有已发布数据集、没有进行中的导入任务、
 * 共享目录下必需 dump 文件齐全且配置开关开启，则自动创建导入任务
 * （等价于管理员调用一次导入 API），复用 sys_tasks → Worker → 五阶段 →
 * 发布 → 广播的完整管线；不绕过任何任务语义。</p>
 *
 * <p>仅在 Worker 运行时角色注册，避免在无消费者的实例上创建永远排队的任务。
 * 多实例同时启动由 DistributedLock + 活跃任务去重双重保护。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class GeoNamesAutoImportLauncher {

    /** 自动导入无登录用户，使用 nil UUID 作为系统操作人占位。 */
    private static final UUID SYSTEM_OPERATOR = new UUID(0L, 0L);
    private static final String LOCK_KEY = "omninest:photo-geo:auto-import";
    private static final Duration LOCK_TTL = Duration.ofMinutes(2);
    private static final List<String> ACTIVE_STATUSES = List.of("QUEUED", "RUNNING", "RETRY_WAIT");

    private final GeoDatasetService geoDatasetService;
    private final TaskRecordService taskRecordService;
    private final PhotosRuntimeConfigService configService;
    private final DistributedLock distributedLock;

    /** 启动完成后检查并按需触发自动导入；任何异常不阻塞应用启动。 */
    @EventListener(ApplicationReadyEvent.class)
    public void autoImportOnStartup() {
        String token = distributedLock.newToken();
        if (!distributedLock.tryLock(LOCK_KEY, token, LOCK_TTL)) {
            log.info("其他实例正在执行 GeoNames 自动导入检查，本实例跳过");
            return;
        }
        try {
            run();
        } catch (RuntimeException ex) {
            log.error("GeoNames 自动导入触发失败", ex);
        } finally {
            distributedLock.unlock(LOCK_KEY, token);
        }
    }

    private void run() {
        if (!configService.isGeoAutoImportEnabled()) {
            log.debug("GeoNames 自动导入开关关闭，跳过");
            return;
        }
        if (geoDatasetService.currentPublishedVersion() != null) {
            log.debug("已有已发布 GeoNames 数据集，无需自动导入");
            return;
        }
        if (!taskRecordService.findActiveTaskIdsByType(
                GeoDatasetService.TASK_TYPE_IMPORT, ACTIVE_STATUSES).isEmpty()) {
            log.info("已有进行中的 GeoNames 导入任务，跳过自动导入");
            return;
        }
        Path importDir = Path.of(geoDatasetService.importRootDir()).normalize();
        for (String file : GeonamesImportService.REQUIRED_DUMP_FILES) {
            if (!Files.isRegularFile(importDir.resolve(file))) {
                log.info("共享目录缺少 {}，跳过 GeoNames 自动导入: dir={}", file, importDir);
                return;
            }
        }

        GeoDatasetService.GeoImportCreated created = geoDatasetService.createImportTask(
                new GeoDatasetService.GeoImportRequest(LocalDate.now().toString(), null),
                SYSTEM_OPERATOR);
        log.info("GeoNames 数据集自动导入已触发: taskId={}, datasetVersion={}",
                created.taskId(), created.datasetVersion());
    }
}
