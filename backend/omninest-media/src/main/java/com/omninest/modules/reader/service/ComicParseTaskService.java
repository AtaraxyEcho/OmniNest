package com.omninest.modules.reader.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.error.StackSummaries;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.reader.domain.ReaderItemSource;
import com.omninest.modules.reader.domain.ReaderSourceStatus;
import com.omninest.modules.reader.event.ComicParseTaskEvent;
import com.omninest.modules.reader.repository.ReaderItemSourceRepository;
import com.omninest.modules.task.service.TaskRecordService;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 漫画解析任务用例服务，负责解析状态机与统一任务状态回写。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ComicParseTaskService {

    private static final String PARSE_ERROR_CODE = "PARSE_ERROR";

    private final ReaderComicManifestService comicManifestService;
    private final ReaderItemSourceRepository sourceRepository;
    private final TaskRecordService taskRecordService;
    private final FileLifecycleGuard fileLifecycleGuard;

    /**
     * 执行漫画解析任务。
     *
     * @param event 解析任务事件
     */
    public void process(ComicParseTaskEvent event) {
        log.info("开始执行漫画解析任务: itemId={}, sourceId={}, fileFormat={}, isRetry={}",
                event.itemId(), event.sourceId(), event.fileFormat(), event.isRetry());
        if (!claimTask(event)) {
            log.debug("漫画解析任务未被领取，跳过重复消息: taskId={}", event.taskId());
            return;
        }
        if (!fileLifecycleGuard.isOwnedProcessable(event.ownerUserId(), event.fileNodeId())) {
            log.info("漫画来源文件已删除或正在永久删除，取消解析任务: taskId={}, fileNodeId={}",
                    event.taskId(), event.fileNodeId());
            markCancelled(event);
            return;
        }
        ReaderItemSource source = sourceRepository.findById(event.sourceId()).orElse(null);
        if (source == null) {
            log.warn("漫画来源不存在，跳过解析任务: sourceId={}", event.sourceId());
            markTaskFailed(event, "漫画来源不存在", null);
            return;
        }
        if (source.getStatus() == ReaderSourceStatus.READY) {
            log.info("漫画来源已就绪，跳过重复解析: sourceId={}", event.sourceId());
            comicManifestService.refreshItemImportStatus(event.itemId());
            markCompleted(event, "漫画来源已就绪");
            return;
        }

        try {
            comicManifestService.parseExistingSource(
                    event.itemId(),
                    event.sourceId(),
                    progress -> updateProgress(event, progress)
            );
            if (taskRecordService.isCancelled(event.taskId())) {
                throw new ReaderImportCancelledException();
            }
            fileLifecycleGuard.requireOwnedWritable(event.ownerUserId(), event.fileNodeId());
            log.info("漫画解析完成: itemId={}, sourceId={}", event.itemId(), event.sourceId());
            markCompleted(event, "漫画解析完成");
        } catch (ReaderImportCancelledException exception) {
            markSourceCancelled(event);
            markCancelled(event);
            log.info("漫画解析任务已按用户请求中断: taskId={}, sourceId={}", event.taskId(), event.sourceId());
        } catch (BusinessException exception) {
            if (isLifecycleCancellation(exception)) {
                log.info("漫画来源文件在解析期间进入永久删除流程，取消任务: taskId={}, fileNodeId={}",
                        event.taskId(), event.fileNodeId());
                markCancelled(event);
                return;
            }
            log.warn("漫画解析业务失败: itemId={}, sourceId={}, error={}",
                    event.itemId(), event.sourceId(), exception.getMessage(), exception);
            markBusinessFailure(event, exception);
        }
    }

    /**
     * 独立提交解析进度，避免长事务结束前前端始终只能看到初始进度。
     */
    private void updateProgress(ComicParseTaskEvent event, int progress) {
        try {
            if (taskRecordService.isCancelled(event.taskId())) {
                throw new ReaderImportCancelledException();
            }
            taskRecordService.updateProgressImmediately(event.taskId(), progress);
        } catch (BusinessException exception) {
            if (ErrorCode.TASK_NOT_FOUND.equals(exception.errorCode())) {
                log.debug("漫画解析任务记录不存在，跳过进度回写: taskId={}", event.taskId());
                return;
            }
            throw exception;
        }
    }

    /**
     * 回写来源与任务的业务失败状态。回写异常继续向上抛出，由消息消费者进入死信队列。
     */
    private void markBusinessFailure(ComicParseTaskEvent event, BusinessException exception) {
        ReaderItemSource failedSource = sourceRepository.findById(event.sourceId()).orElse(null);
        if (failedSource != null && failedSource.getStatus() != ReaderSourceStatus.READY) {
            failedSource.setStatus(ReaderSourceStatus.FAILED);
            failedSource.setErrorCode(PARSE_ERROR_CODE);
            failedSource.setErrorMessage(exception.getMessage());
            sourceRepository.save(failedSource);
        }
        comicManifestService.refreshItemImportStatus(event.itemId());
        markTaskFailed(event, exception.getMessage(), StackSummaries.summarize(exception));
    }

    private boolean claimTask(ComicParseTaskEvent event) {
        try {
            return taskRecordService.claimForExecution(event.taskId(), "PARSING_SOURCE");
        } catch (BusinessException exception) {
            if (ErrorCode.TASK_NOT_FOUND.equals(exception.errorCode())) {
                log.debug("漫画解析任务记录不存在，按历史消息继续处理: taskId={}", event.taskId());
                return true;
            }
            throw exception;
        }
    }

    /**
     * 标记统一任务完成，兼容历史消息没有任务记录的情况。
     */
    private void markCompleted(ComicParseTaskEvent event, String message) {
        try {
            taskRecordService.markCompleted(event.taskId(), Map.of(
                    "itemId", event.itemId().toString(),
                    "sourceId", event.sourceId().toString(),
                    "message", message
            ));
        } catch (BusinessException exception) {
            if (ErrorCode.TASK_NOT_FOUND.equals(exception.errorCode())) {
                log.debug("漫画解析任务记录不存在，跳过完成回写: taskId={}", event.taskId());
                return;
            }
            throw exception;
        }
    }

    /**
     * 标记统一任务失败，兼容历史消息没有任务记录的情况。
     */
    private void markTaskFailed(ComicParseTaskEvent event, String errorMessage, String stackSummary) {
        try {
            taskRecordService.markFailed(event.taskId(), errorMessage, stackSummary);
        } catch (BusinessException exception) {
            if (ErrorCode.TASK_NOT_FOUND.equals(exception.errorCode())) {
                log.debug("漫画解析任务记录不存在，跳过失败回写: taskId={}", event.taskId());
                return;
            }
            throw exception;
        }
    }

    private void markCancelled(ComicParseTaskEvent event) {
        try {
            taskRecordService.markCancelled(event.taskId());
        } catch (BusinessException exception) {
            if (ErrorCode.TASK_NOT_FOUND.equals(exception.errorCode())) {
                log.debug("漫画解析任务记录不存在，跳过取消回写: taskId={}", event.taskId());
                return;
            }
            throw exception;
        }
    }

    private void markSourceCancelled(ComicParseTaskEvent event) {
        ReaderItemSource source = sourceRepository.findById(event.sourceId()).orElse(null);
        if (source != null) {
            source.setStatus(ReaderSourceStatus.FAILED);
            source.setErrorCode("IMPORT_CANCELLED");
            source.setErrorMessage("用户已取消导入");
            sourceRepository.save(source);
        }
        comicManifestService.refreshItemImportStatus(event.itemId());
    }

    private boolean isLifecycleCancellation(BusinessException exception) {
        return ErrorCode.FILE_LIFECYCLE_CONFLICT.equals(exception.errorCode())
                || ErrorCode.FILE_NOT_FOUND.equals(exception.errorCode());
    }
}
