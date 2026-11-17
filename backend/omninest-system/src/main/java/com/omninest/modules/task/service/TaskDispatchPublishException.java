package com.omninest.modules.task.service;

/**
 * 描述任务消息发布失败的稳定分类和可重试语义。
 *
 * @author OmniNest
 */
final class TaskDispatchPublishException extends RuntimeException {

    private final String errorCode;
    private final boolean retryable;
    private final String failureType;

    TaskDispatchPublishException(
            String errorCode,
            boolean retryable,
            String failureType,
            String message,
            Throwable cause
    ) {
        super(message, cause);
        this.errorCode = errorCode;
        this.retryable = retryable;
        this.failureType = failureType;
    }

    String errorCode() {
        return errorCode;
    }

    boolean retryable() {
        return retryable;
    }

    String failureType() {
        return failureType;
    }
}
