package com.omninest.worker.media;

import com.omninest.worker.runtime.ConditionalOnWorkerRuntime;

import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileDescriptor;
import com.omninest.modules.file.event.FileUploadedEvent;
import com.omninest.modules.file.event.MediaAutoImportRequestedEvent;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.media.service.MediaImportHandler;
import com.omninest.modules.media.service.MediaImportResult;
import com.omninest.modules.notification.port.NotificationPublisher;
import com.omninest.modules.task.service.TaskRecordService;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 媒体自动导入任务执行服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
@ConditionalOnWorkerRuntime
public class MediaAutoImportExecutionService {
    private final List<MediaImportHandler> handlers;
    private final TaskRecordService taskRecordService;
    private final FileLifecycleGuard fileLifecycleGuard;
    private final NotificationPublisher notificationPublisher;

    /**
     * 执行媒体自动导入任务。
     *
     * @param event 媒体自动导入任务消息
     */
    public void execute(MediaAutoImportRequestedEvent event) {
        if (!taskRecordService.claimForExecution(event.taskId(), "DETECTING")) {
            return;
        }

        FileUploadedEvent file = event.file();
        FileDescriptor descriptor = fileLifecycleGuard.requireOwnedWritable(
                file.ownerUserId(),
                file.fileNodeId()
        );
        Map<String, Map<String, Object>> outcomes = loadOutcomes(event.taskId());
        int totalHandlers = Math.max(1, handlers.size());
        for (int index = 0; index < handlers.size(); index++) {
            MediaImportHandler handler = handlers.get(index);
            Map<String, Object> previousOutcome = outcomes.get(handler.module());
            if (previousOutcome != null && "SUCCEEDED".equals(previousOutcome.get("status"))) {
                persistProgress(event.taskId(), outcomes, index + 1, totalHandlers);
                continue;
            }
            if (!isSupported(handler, file, descriptor)) {
                outcomes.put(handler.module(), outcome(handler.module(), "SKIPPED", null, null));
                persistProgress(event.taskId(), outcomes, index + 1, totalHandlers);
                continue;
            }

            fileLifecycleGuard.requireOwnedWritable(file.ownerUserId(), file.fileNodeId());
            try {
                MediaImportResult result = handler.importFile(file);
                outcomes.put(
                        handler.module(),
                        outcome(handler.module(), "SUCCEEDED", result.resourceId(), null)
                );
                persistProgress(event.taskId(), outcomes, index + 1, totalHandlers);
            } catch (RuntimeException exception) {
                outcomes.put(handler.module(), outcome(
                                handler.module(),
                                "FAILED",
                                null,
                                exception.getClass().getSimpleName()
                        ));
                taskRecordService.updateResult(event.taskId(), resultPayload(outcomes));
                throw exception;
            }
        }

        fileLifecycleGuard.requireOwnedWritable(file.ownerUserId(), file.fileNodeId());
        taskRecordService.markCompleted(event.taskId(), resultPayload(outcomes));
        // 通知文案由前端按类型与 metadata 本地化，后端只落语义载荷。
        notificationPublisher.notifyOrLog(
                file.ownerUserId(),
                "MEDIA_AUTO_IMPORT_COMPLETED",
                null,
                null,
                Map.of(
                        "taskId", event.taskId().toString(),
                        "fileNodeId", file.fileNodeId().toString(),
                        "fileName", file.fileName()
                )
        );
        log.info("媒体自动导入任务完成: taskId={}, fileNodeId={}, handlerCount={}",
                event.taskId(), file.fileNodeId(), handlers.size());
    }

    private boolean isSupported(
            MediaImportHandler handler,
            FileUploadedEvent file,
            FileDescriptor descriptor
    ) {
        if ("PHOTOS".equals(handler.module()) && !SpaceType.PERSONAL.equals(descriptor.spaceType())) {
            return false;
        }
        return handler.supports(file);
    }

    private void persistProgress(
            UUID taskId,
            Map<String, Map<String, Object>> outcomes,
            int completedHandlers,
            int totalHandlers
    ) {
        taskRecordService.updateResult(taskId, resultPayload(outcomes));
        int progress = 10 + (completedHandlers * 80 / totalHandlers);
        taskRecordService.updateExecution(taskId, "IMPORTING", progress);
    }

    private Map<String, Object> resultPayload(Map<String, Map<String, Object>> outcomes) {
        return Map.of("handlers", List.copyOf(outcomes.values()));
    }

    private Map<String, Map<String, Object>> loadOutcomes(UUID taskId) {
        Map<String, Map<String, Object>> outcomes = new LinkedHashMap<>();
        Object rawHandlers = taskRecordService.taskResult(taskId).get("handlers");
        if (!(rawHandlers instanceof List<?> handlerResults)) {
            return outcomes;
        }
        for (Object rawResult : handlerResults) {
            if (!(rawResult instanceof Map<?, ?> result)) {
                continue;
            }
            Object rawModule = result.get("module");
            if (rawModule == null) {
                continue;
            }
            Map<String, Object> normalized = new LinkedHashMap<>();
            result.forEach((key, value) -> normalized.put(String.valueOf(key), value));
            outcomes.put(String.valueOf(rawModule), Map.copyOf(normalized));
        }
        return outcomes;
    }

    private Map<String, Object> outcome(
            String module,
            String status,
            UUID resourceId,
            String errorCode
    ) {
        Map<String, Object> outcome = new LinkedHashMap<>();
        outcome.put("module", module);
        outcome.put("status", status);
        if (resourceId != null) {
            outcome.put("resourceId", resourceId.toString());
        }
        if (errorCode != null) {
            outcome.put("errorCode", errorCode);
        }
        return Map.copyOf(outcome);
    }
}
