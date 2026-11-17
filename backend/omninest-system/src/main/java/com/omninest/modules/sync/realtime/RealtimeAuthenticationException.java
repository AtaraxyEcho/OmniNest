package com.omninest.modules.sync.realtime;

import org.springframework.security.access.AccessDeniedException;

/**
 * STOMP 实时连接认证或授权失败异常。
 *
 * @author OmniNest
 */
public class RealtimeAuthenticationException extends AccessDeniedException {

    /**
     * 使用错误消息创建异常。
     *
     * @param message 错误消息
     */
    public RealtimeAuthenticationException(String message) {
        super(message);
    }

    /**
     * 使用错误消息和原始异常创建异常。
     *
     * @param message 错误消息
     * @param cause 原始异常
     */
    public RealtimeAuthenticationException(String message, Throwable cause) {
        super(message, cause);
    }
}
