package com.omninest.common.ratelimit;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import java.util.Map;
import java.util.function.Supplier;
import java.util.regex.Pattern;
import lombok.extern.slf4j.Slf4j;
import org.slf4j.MDC;

/**
 * 统一执行 Redis 限流操作并将依赖故障转换为稳定业务错误。
 *
 * @author OmniNest
 */
@Slf4j
final class RedisRateLimitExecutor {

    private static final String DEPENDENCY = "redis";
    private static final String REQUEST_ID_MDC_KEY = "requestId";
    private static final String UNAVAILABLE_REQUEST_ID = "unavailable";
    private static final Pattern SAFE_REQUEST_ID = Pattern.compile("[A-Za-z0-9._-]{1,128}");

    private RedisRateLimitExecutor() {
    }

    /**
     * 执行 Redis 操作。连接、超时、脚本错误及空结果均按 fail-closed 处理。
     *
     * @param capability 固定的限流能力名称，不得传入用户或请求派生数据
     * @param operation Redis 操作
     * @param <T> 返回值类型
     * @return 非空执行结果
     * @throws BusinessException Redis 不可用或返回无效结果时抛出
     */
    static <T> T execute(String capability, Supplier<T> operation) {
        try {
            T result = operation.get();
            if (result == null) {
                throw dependencyUnavailable(capability, "NULL_RESULT");
            }
            return result;
        } catch (BusinessException exception) {
            throw exception;
        } catch (RuntimeException exception) {
            throw dependencyUnavailable(capability, exception.getClass().getSimpleName());
        }
    }

    private static BusinessException dependencyUnavailable(String capability, String failureType) {
        log.error(
                "限流依赖不可用: dependency={}, capability={}, requestId={}, failureType={}",
                DEPENDENCY,
                capability,
                safeRequestId(),
                failureType
        );
        return new BusinessException(
                ErrorCode.DEPENDENCY_UNAVAILABLE,
                "限流服务暂不可用，请稍后重试",
                Map.of("dependency", DEPENDENCY, "capability", capability)
        );
    }

    private static String safeRequestId() {
        String requestId = MDC.get(REQUEST_ID_MDC_KEY);
        if (requestId == null || !SAFE_REQUEST_ID.matcher(requestId).matches()) {
            return UNAVAILABLE_REQUEST_ID;
        }
        return requestId;
    }
}
