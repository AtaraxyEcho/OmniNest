package com.omninest.common.error;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.enums.ErrorCode;
import jakarta.validation.ConstraintViolationException;
import java.util.stream.Collectors;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.authorization.AuthorizationDeniedException;
import org.springframework.validation.BindException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.context.request.async.AsyncRequestNotUsableException;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.web.servlet.NoHandlerFoundException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

/**
 * 统一处理 REST 请求与异步响应异常。
 *
 * @author Notask Flow Team
 */
@Slf4j
@RestControllerAdvice
public class GlobalExceptionHandler {

    @ExceptionHandler(BusinessException.class)
    ResponseEntity<ApiResponse<Void>> handleBusiness(BusinessException exception) {
        log.warn("业务异常: code={}, message={}", exception.errorCode().getCode(), exception.getMessage());
        HttpStatus status = switch (exception.errorCode()) {
            case UNAUTHORIZED -> HttpStatus.UNAUTHORIZED;
            case FORBIDDEN, REGISTRATION_DISABLED -> HttpStatus.FORBIDDEN;
            case NOT_FOUND, TASK_NOT_FOUND, CONFIG_NOT_FOUND, FILE_NOT_FOUND,
                    MEDIA_NOT_FOUND, BOOK_NOT_FOUND, BACKDROP_NOT_FOUND -> HttpStatus.NOT_FOUND;
            case RATE_LIMITED -> HttpStatus.TOO_MANY_REQUESTS;
            case BACKDROP_FILE_TOO_LARGE -> HttpStatus.PAYLOAD_TOO_LARGE;
            case BACKDROP_UNSUPPORTED_FORMAT -> HttpStatus.UNPROCESSABLE_ENTITY;
            case DEPENDENCY_UNAVAILABLE -> HttpStatus.SERVICE_UNAVAILABLE;
            case CONFLICT, TASK_STATUS_ILLEGAL, TASK_ALREADY_COMPLETED,
                    PREFERENCE_VERSION_CONFLICT, RESOURCE_IN_USE,
                    FILE_LIFECYCLE_CONFLICT -> HttpStatus.CONFLICT;
            default -> HttpStatus.BAD_REQUEST;
        };
        Object details = exception.details().isEmpty() ? null : exception.details();
        return ResponseEntity.status(status)
                .body(ApiResponse.error(exception.errorCode(), exception.getMessage(), details));
    }

    @ExceptionHandler(ObjectOptimisticLockingFailureException.class)
    ResponseEntity<ApiResponse<Void>> handleOptimisticLockingFailure(
            ObjectOptimisticLockingFailureException exception
    ) {
        log.warn("并发更新冲突: errorType={}, entity={}, entityId={}, detail={}",
                exception.getClass().getSimpleName(),
                exception.getPersistentClassName(),
                exception.getIdentifier(),
                exception.getMessage(),
                exception);
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(ApiResponse.error(ErrorCode.CONFLICT, "资源正在被其他请求更新，请稍后重试"));
    }

    @ExceptionHandler({MethodArgumentNotValidException.class, ConstraintViolationException.class})
    ResponseEntity<ApiResponse<Void>> handleValidation(Exception exception) {
        return ResponseEntity.badRequest()
                .body(ApiResponse.error(ErrorCode.PARAM_ERROR, resolveValidationMessage(exception)));
    }

    @ExceptionHandler(BindException.class)
    ResponseEntity<ApiResponse<Void>> handleBindException(BindException exception) {
        return ResponseEntity.badRequest()
                .body(ApiResponse.error(ErrorCode.PARAM_ERROR, fieldErrorMessage(exception)));
    }

    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    ResponseEntity<ApiResponse<Void>> handleTypeMismatch(MethodArgumentTypeMismatchException exception) {
        return ResponseEntity.badRequest()
                .body(ApiResponse.error(ErrorCode.PARAM_ERROR, "参数 " + exception.getName() + " 格式不正确"));
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    ResponseEntity<ApiResponse<Void>> handleNotReadable(HttpMessageNotReadableException exception) {
        log.warn("请求体解析异常: {}", exception.getMessage());
        return ResponseEntity.badRequest().body(ApiResponse.error(ErrorCode.PARAM_ERROR, "请求体格式不正确或枚举值不受支持"));
    }

    @ExceptionHandler(AuthorizationDeniedException.class)
    ResponseEntity<ApiResponse<Void>> handleAccessDenied(AuthorizationDeniedException exception) {
        log.warn("权限不足: {}", exception.getMessage());
        return ResponseEntity.status(HttpStatus.FORBIDDEN)
                .body(ApiResponse.error(ErrorCode.FORBIDDEN, "权限不足，无法执行此操作"));
    }

    @ExceptionHandler(HttpRequestMethodNotSupportedException.class)
    ResponseEntity<ApiResponse<Void>> handleMethodNotSupported(HttpRequestMethodNotSupportedException exception) {
        log.warn("请求方法不支持: {}", exception.getMethod());
        return ResponseEntity.status(HttpStatus.METHOD_NOT_ALLOWED)
                .body(ApiResponse.error(ErrorCode.BAD_REQUEST, "请求方法 " + exception.getMethod() + " 不支持"));
    }

    @ExceptionHandler(NoHandlerFoundException.class)
    ResponseEntity<ApiResponse<Void>> handleNoHandlerFound(NoHandlerFoundException exception) {
        logUnknownPath(exception.getHttpMethod(), exception.getRequestURL());
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(ApiResponse.error(ErrorCode.NOT_FOUND, "接口不存在"));
    }

    @ExceptionHandler(NoResourceFoundException.class)
    ResponseEntity<ApiResponse<Void>> handleNoResourceFound(NoResourceFoundException exception) {
        logUnknownPath(exception.getHttpMethod().name(), exception.getResourcePath());
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(ApiResponse.error(ErrorCode.NOT_FOUND, "接口不存在"));
    }

    // API 路径缺失是真实的接口契约信号，保持 WARN；
    // 静态资源缺失（webapp 未部署、扫描器探测）降为 DEBUG，避免污染错误日志。
    private void logUnknownPath(String method, String path) {
        String normalized = path == null ? "" : path;
        if (normalized.startsWith("/api/") || normalized.startsWith("api/")) {
            log.warn("接口不存在: {} {}", method, normalized);
        } else {
            log.debug("资源不存在: {} {}", method, normalized);
        }
    }

    @ExceptionHandler(AsyncRequestNotUsableException.class)
    void handleAsyncRequestNotUsable(AsyncRequestNotUsableException exception) {
        log.debug("客户端已断开异步请求: {}", exception.getMessage());
    }

    @ExceptionHandler(Exception.class)
    ResponseEntity<ApiResponse<Void>> handleUnexpected(Exception exception) {
        log.error("未知系统异常", exception);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(ApiResponse.error(ErrorCode.INTERNAL_ERROR, "系统繁忙，请稍后重试"));
    }

    private String resolveValidationMessage(Exception exception) {
        if (exception instanceof MethodArgumentNotValidException methodArgumentNotValidException) {
            return fieldErrorMessage(methodArgumentNotValidException);
        }
        return exception.getMessage() == null ? ErrorCode.PARAM_ERROR.getMessage() : exception.getMessage();
    }

    private String fieldErrorMessage(MethodArgumentNotValidException exception) {
        return exception.getBindingResult().getFieldErrors().stream()
                .map(error -> error.getField() + ":" + error.getDefaultMessage())
                .collect(Collectors.joining(";"));
    }

    private String fieldErrorMessage(BindException exception) {
        return exception.getBindingResult().getFieldErrors().stream()
                .map(error -> error.getField() + ":" + error.getDefaultMessage())
                .collect(Collectors.joining(";"));
    }
}
