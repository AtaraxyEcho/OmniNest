package com.omninest.modules.reader.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.service.FileLifecycleGuard;
import com.omninest.modules.reader.event.ReaderParseTaskEvent;
import com.omninest.modules.reader.service.ReaderTextParser.ParsedTextBook;
import com.omninest.modules.task.service.TaskRecordService;
import com.omninest.common.util.ThrowableDescriber;
import java.util.Map;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 文本书籍解析任务用例服务。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ReaderTextParseTaskService {

    private final ReaderTextParser textParser;
    private final ReaderTextManifestService manifestService;
    private final TaskRecordService taskRecordService;
    private final FileLifecycleGuard fileLifecycleGuard;

    /**
     * 执行文本书籍解析任务。
     *
     * @param event 解析任务消息
     */
    public void process(ReaderParseTaskEvent event) {
        if (!taskRecordService.claimForExecution(event.taskId(), "PARSING_METADATA")) {
            log.debug("文本书籍解析任务未被领取，跳过重复消息: taskId={}", event.taskId());
            return;
        }
        if (!fileLifecycleGuard.isOwnedProcessable(event.ownerUserId(), event.fileNodeId())) {
            taskRecordService.markCancelled(event.taskId());
            return;
        }
        try {
            ParsedTextBook parsedBook = textParser.parse(
                    event.fileNodeId(),
                    event.fileFormat(),
                    progress -> updateProgress(event, progress)
            );
            if (taskRecordService.isCancelled(event.taskId())) {
                throw new ReaderImportCancelledException();
            }
            fileLifecycleGuard.requireOwnedWritable(event.ownerUserId(), event.fileNodeId());
            manifestService.replaceManifest(event.itemId(), parsedBook);
            taskRecordService.markCompleted(event.taskId(), Map.of(
                    "itemId", event.itemId().toString(),
                    "chapterCount", parsedBook.chapters().size(),
                    "message", "文本书籍解析完成"
            ));
            log.info("文本书籍解析完成: taskId={}, itemId={}, chapterCount={}",
                    event.taskId(), event.itemId(), parsedBook.chapters().size());
        } catch (ReaderImportCancelledException exception) {
            manifestService.markFailed(event.itemId(), "IMPORT_CANCELLED", "用户已取消导入");
            taskRecordService.markCancelled(event.taskId());
            log.info("文本书籍解析任务已按用户请求中断: taskId={}, itemId={}", event.taskId(), event.itemId());
        } catch (BusinessException exception) {
            if (isLifecycleCancellation(exception)) {
                taskRecordService.markCancelled(event.taskId());
                return;
            }
            manifestService.markFailed(event.itemId(), exception.errorCode().name(), exception.getMessage());
            taskRecordService.markFailed(event.taskId(), exception.getMessage(), ThrowableDescriber.describe(exception));
            log.warn("文本书籍解析业务失败: taskId={}, itemId={}, errorCode={}",
                    event.taskId(), event.itemId(), exception.errorCode().getCode());
        }
    }

    private void updateProgress(ReaderParseTaskEvent event, int progress) {
        if (taskRecordService.isCancelled(event.taskId())) {
            throw new ReaderImportCancelledException();
        }
        taskRecordService.updateProgressImmediately(event.taskId(), progress);
    }

    private boolean isLifecycleCancellation(BusinessException exception) {
        return ErrorCode.FILE_LIFECYCLE_CONFLICT.equals(exception.errorCode())
                || ErrorCode.FILE_NOT_FOUND.equals(exception.errorCode());
    }
}
