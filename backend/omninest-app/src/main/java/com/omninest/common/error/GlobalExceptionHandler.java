package com.omninest.common.error;

import com.alibaba.fastjson2.JSON;
import com.omninest.common.api.ApiResponse;
import com.omninest.common.enums.ErrorCode;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.ConstraintViolationException;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.format.DateTimeParseException;
import java.util.Locale;
import java.util.stream.Collectors;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.orm.ObjectOptimisticLockingFailureException;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.security.authorization.AuthorizationDeniedException;
import org.springframework.transaction.IllegalTransactionStateException;
import org.springframework.validation.BindException;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.context.request.async.AsyncRequestNotUsableException;
import org.springframework.web.context.request.async.AsyncRequestTimeoutException;
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
            case UNAUTHORIZED, PASSWORD_INVALID, SHARE_PASSWORD_REQUIRED -> HttpStatus.UNAUTHORIZED;
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
                .contentType(MediaType.APPLICATION_JSON)
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

    // 缺失必填 @RequestParam 落入通用 Exception 处理器返回 500；按参数错误返回 400。
    @ExceptionHandler(MissingServletRequestParameterException.class)
    ResponseEntity<ApiResponse<Void>> handleMissingParameter(MissingServletRequestParameterException exception) {
        return ResponseEntity.badRequest()
                .body(ApiResponse.error(ErrorCode.PARAM_ERROR, "缺少必填参数: " + exception.getParameterName()));
    }

    // FastJson 按全局日期格式解析失败时抛出 DateTimeParseException，属请求体格式问题而非系统故障。
    @ExceptionHandler(DateTimeParseException.class)
    ResponseEntity<ApiResponse<Void>> handleDateTimeParse(DateTimeParseException exception) {
        log.warn("日期时间格式解析失败: {}", exception.getMessage());
        return ResponseEntity.badRequest()
                .body(ApiResponse.error(ErrorCode.PARAM_ERROR, "日期时间格式不正确，支持 yyyy-MM-dd HH:mm:ss 与 ISO-8601"));
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
    // 静态资源缺失（扫描器探测等）降为 DEBUG，避免污染错误日志。
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

    /**
     * 异步请求超时（含流式响应被容器回收）不再写入错误体。
     *
     * <p>流式接口返回时已预设 {@code audio/*} 等媒体 Content-Type，
     * 全局异常再写 {@link ApiResponse} 会触发 {@code HttpMessageNotWritableException}
     * 并二次打错误日志。超时属可预期生命周期，按客户端侧中断降级处理。</p>
     */
    @ExceptionHandler(AsyncRequestTimeoutException.class)
    void handleAsyncRequestTimeout(AsyncRequestTimeoutException exception) {
        log.debug("异步请求超时: {}", exception.getMessage());
    }

    /**
     * 客户端断开或上游读中断导致的 IO 异常不写入 JSON 错误体。
     *
     * <p>StreamingResponseBody 在写出阶段抛出的 IOException 常常伴随
     * InterruptedException 包装（HttpClient 响应流被取消），此时响应头已固定为
     * 媒体类型，继续返回 ApiResponse 会触发转换器失败。</p>
     */
    @ExceptionHandler(IOException.class)
    void handleIoException(IOException exception) {
        if (isClientDisconnect(exception)) {
            log.debug("流式响应已中断: {}", exception.getMessage());
            return;
        }
        log.warn("IO 异常: {}", exception.getMessage());
    }

    /**
     * 事务传播状态错误是编程错误而非运行环境故障。
     *
     * <p>典型场景：以 {@code Propagation.MANDATORY} 声明的记录器被无事务的调用方调用，
     * 抛出 {@code IllegalTransactionStateException}。此类错误若混入"未知系统异常"难以定位，
     * 因此单独打点，响应体与通用分支保持一致，避免向前端泄露内部实现。</p>
     */
    @ExceptionHandler(IllegalTransactionStateException.class)
    ResponseEntity<ApiResponse<Void>> handleIllegalTransactionState(
            IllegalTransactionStateException exception
    ) {
        log.error("事务传播状态错误，请核查调用方事务边界: message={}", exception.getMessage(), exception);
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(ApiResponse.error(ErrorCode.INTERNAL_ERROR, "系统繁忙，请稍后重试"));
    }

    @ExceptionHandler(Exception.class)
    void handleUnexpected(Exception exception, HttpServletResponse response) throws IOException {
        if (isClientDisconnect(exception) || exception instanceof AsyncRequestTimeoutException) {
            log.debug("请求已中断，跳过错误响应: {}", exception.getMessage());
            return;
        }
        log.error("未知系统异常", exception);
        if (response.isCommitted()) {
            log.warn("响应已提交，跳过错误体写出: status={}", response.getStatus());
            return;
        }
        response.setStatus(HttpStatus.INTERNAL_SERVER_ERROR.value());
        if (!isJsonWritable(response)) {
            log.warn("Content-Type 非 JSON，跳过错误体写出: contentType={}", response.getContentType());
            return;
        }
        response.setCharacterEncoding(StandardCharsets.UTF_8.name());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.getWriter().write(JSON.toJSONString(
                ApiResponse.error(ErrorCode.INTERNAL_ERROR, "系统繁忙，请稍后重试")));
    }

    /**
     * 流式响应预设了媒体 Content-Type 后，不能再按 JSON 写出 ApiResponse。
     */
    private boolean isJsonWritable(HttpServletResponse response) {
        String contentType = response.getContentType();
        if (contentType == null || contentType.isBlank()) {
            return true;
        }
        String lower = contentType.toLowerCase(Locale.ROOT);
        return lower.contains("json") || lower.startsWith("text/");
    }

    /**
     * 判断异常是否属于客户端断开或异步取消导致的中断。
     */
    private boolean isClientDisconnect(Throwable throwable) {
        Throwable current = throwable;
        while (current != null) {
            if (current instanceof InterruptedException
                    || current instanceof AsyncRequestNotUsableException) {
                return true;
            }
            String message = current.getMessage();
            if (message != null) {
                String lower = message.toLowerCase(Locale.ROOT);
                if (lower.contains("broken pipe")
                        || lower.contains("connection reset")
                        || lower.contains("connection aborted")
                        || lower.contains("client abort")
                        || lower.contains("an established connection was aborted")) {
                    return true;
                }
            }
            current = current.getCause() == current ? null : current.getCause();
        }
        return false;
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
