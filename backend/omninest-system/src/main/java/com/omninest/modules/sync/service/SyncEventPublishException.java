package com.omninest.modules.sync.service;

/**
 * 同步事件未获得 RabbitMQ 发布确认时抛出的异常。
 *
 * @author OmniNest
 */
public class SyncEventPublishException extends RuntimeException {

    /**
     * 使用错误消息创建异常。
     *
     * @param message 错误消息
     */
    public SyncEventPublishException(String message) {
        super(message);
    }

    /**
     * 使用错误消息和原始异常创建异常。
     *
     * @param message 错误消息
     * @param cause 原始异常
     */
    public SyncEventPublishException(String message, Throwable cause) {
        super(message, cause);
    }
}
