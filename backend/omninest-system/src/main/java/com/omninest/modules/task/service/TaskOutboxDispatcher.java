package com.omninest.modules.task.service;

import com.omninest.modules.task.config.TaskOutboxProperties;
import java.time.Instant;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

/**
 * 任务 Outbox 调度器。
 *
 * <p>所有运行角色都会轮询：worker 与 scheduler 自身也会写入 task_dispatches，
 * 只由 api 派发会让这些角色在 api 重启或缩容时整条任务链停摆。认领基于
 * {@code FOR UPDATE SKIP LOCKED} 与实例租约，多实例并发安全。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class TaskOutboxDispatcher {
    private final TaskDispatchService dispatchService;
    private final RabbitTaskDispatchPublisher publisher;
    private final TaskOutboxProperties properties;

    /**
     * 定时发布一批任务消息。
     */
    @Scheduled(fixedDelayString = "${omninest.task.outbox.interval-millis:500}")
    public void dispatch() {
        if (!properties.isEnabled()) {
            return;
        }
        dispatchService.claimBatch(Instant.now()).forEach(this::publishOne);
    }

    private void publishOne(ClaimedTaskDispatch dispatch) {
        if (dispatchService.isDeadLetterPending(dispatch)) {
            publishDeadLetter(
                    dispatch,
                    dispatchService.deadLetterErrorCode(dispatch),
                    "DEAD_LETTER_RETRY"
            );
            return;
        }
        try {
            publisher.publish(dispatch);
            if (!dispatchService.markPublished(dispatch.id(), Instant.now())) {
                log.warn("任务消息发布成功但租约已变化: dispatchId={}, taskId={}",
                        dispatch.id(), dispatch.taskId());
            }
        } catch (TaskDispatchPublishException exception) {
            handlePublishFailure(dispatch, exception);
        } catch (RuntimeException exception) {
            handlePublishFailure(dispatch, new TaskDispatchPublishException(
                    "UNEXPECTED_PUBLISH_ERROR",
                    true,
                    exception.getClass().getSimpleName(),
                    "任务消息发布出现未分类错误",
                    exception
            ));
        }
    }

    private void handlePublishFailure(
            ClaimedTaskDispatch dispatch,
            TaskDispatchPublishException exception
    ) {
        if (dispatchService.requiresDeadLetter(dispatch, exception.retryable())) {
            publishDeadLetter(dispatch, exception.errorCode(), exception.failureType());
            return;
        }
        boolean updated = dispatchService.markFailed(
                dispatch,
                Instant.now(),
                exception.errorCode()
        );
        log.warn("任务消息发布失败并等待重试: dispatchId={}, taskId={}, stateUpdated={}, errorCode={}",
                dispatch.id(), dispatch.taskId(), updated, exception.errorCode());
    }

    private void publishDeadLetter(
            ClaimedTaskDispatch dispatch,
            String originalErrorCode,
            String failureType
    ) {
        Instant failedAt = Instant.now();
        try {
            publisher.publishDeadLetter(dispatch, originalErrorCode, failureType, failedAt);
            boolean updated = dispatchService.markDeadLetterPublished(
                    dispatch,
                    Instant.now(),
                    originalErrorCode
            );
            log.error("任务消息已转入死信: dispatchId={}, taskId={}, stateUpdated={}, errorCode={}",
                    dispatch.id(), dispatch.taskId(), updated, originalErrorCode);
        } catch (RuntimeException exception) {
            boolean updated = dispatchService.markDeadLetterPublishFailed(
                    dispatch,
                    failedAt,
                    originalErrorCode
            );
            log.error("任务死信发布失败并等待恢复: dispatchId={}, taskId={}, stateUpdated={}, errorType={}",
                    dispatch.id(), dispatch.taskId(), updated, exception.getClass().getSimpleName());
        }
    }
}
