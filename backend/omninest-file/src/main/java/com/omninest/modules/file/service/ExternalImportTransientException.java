package com.omninest.modules.file.service;

/**
 * 外部存储导入的瞬时失败载体。
 *
 * <p>执行侧的受检异常无法在不改方法签名的前提下穿透到消费者；包装一层保留原始 cause，
 * 由 {@code ExternalImportRetryService} 沿 cause 链分类与摘要，避免把 IOException
 * 误判成一种新的业务错误。</p>
 *
 * @author OmniNest
 */
public class ExternalImportTransientException extends RuntimeException {

    ExternalImportTransientException(Throwable cause) {
        super(cause.getMessage(), cause);
    }

    /**
     * 运行时异常原样透传，受检异常包装后抛出。
     *
     * @param exception 原始异常
     * @return 可直接抛出的运行时异常
     */
    static RuntimeException wrap(Exception exception) {
        if (exception instanceof RuntimeException runtimeException) {
            return runtimeException;
        }
        return new ExternalImportTransientException(exception);
    }
}
