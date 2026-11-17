package com.omninest.common.error;

import com.omninest.common.enums.ErrorCode;
import java.util.Map;

/**
 * 携带稳定错误码和结构化详情的业务异常。
 *
 * @author OmniNest
 */
public class BusinessException extends RuntimeException {
    private final ErrorCode errorCode;
    private final Map<String, Object> details;

    /**
     * 创建不包含结构化详情的业务异常。
     *
     * @param errorCode 稳定错误码
     * @param message 错误消息
     */
    public BusinessException(ErrorCode errorCode, String message) {
        this(errorCode, message, Map.of());
    }

    /**
     * 创建包含结构化详情的业务异常。
     *
     * @param errorCode 稳定错误码
     * @param message 错误消息
     * @param details 结构化错误详情
     */
    public BusinessException(ErrorCode errorCode, String message, Map<String, Object> details) {
        super(message);
        this.errorCode = errorCode;
        this.details = details == null ? Map.of() : details;
    }

    /**
     * 获取稳定错误码。
     *
     * @return 稳定错误码
     */
    public ErrorCode errorCode() {
        return errorCode;
    }

    /**
     * 获取结构化错误详情。
     *
     * @return 不可为空的错误详情
     */
    public Map<String, Object> details() {
        return details;
    }
}
