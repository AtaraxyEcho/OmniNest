package com.omninest.common.error;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.json.JsonSupport;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.ConstraintViolationException;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.format.DateTimeParseException;
import java.util.Locale;
import java.util.stream.Collectors;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
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
import org.springframework.web.multipart.MaxUploadSizeExceededException;
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
                    MEDIA_NOT_FOUND, BOOK_NOT_FOUND, BACKDROP_NOT_FOUND,
                    CHAPTER_TEXT_UNAVAILABLE -> HttpStatus.NOT_FOUND;
            case RATE_LIMITED -> HttpStatus.TOO_MANY_REQUESTS;
            case FILE_SIZE_EXCEEDED, BACKDROP_FILE_TOO_LARGE -> HttpStatus.CONTENT_TOO_LARGE;
            case BACKDROP_UNSUPPORTED_FORMAT -> HttpStatus.UNPROCESSABLE_CONTENT;
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

    /**
     * 并发写入触发数据库唯一约束或数据完整性冲突时返回 409，而不是落到兜底 500。
     */
    @ExceptionHandler(DataIntegrityViolationException.class)
    ResponseEntity<ApiResponse<Void>> handleDataIntegrityViolation(DataIntegrityViolationException exception) {
        // 数据库异常消息可能带唯一键里的文件名等业务数据，只记录异常类型。
        log.warn("数据完整性冲突: errorType={}", exception.getClass().getSimpleName());
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(ApiResponse.error(ErrorCode.CONFLICT, "数据冲突，请稍后重试"));
    }

    /**
     * Multipart 上传超过容器或框架限制时返回 413，避免客户端误以为服务端故障。
     */
    @ExceptionHandler(MaxUploadSizeExceededException.class)
    ResponseEntity<ApiResponse<Void>> handleMaxUploadSize(MaxUploadSizeExceededException exception) {
        log.warn("上传文件超过大小限制: maxUploadSize={}",
                exception.getMaxUploadSize() > 0 ? exception.getMaxUploadSize() : "unknown");
        return ResponseEntity.status(HttpStatus.CONTENT_TOO_LARGE)
                .body(ApiResponse.error(ErrorCode.FILE_SIZE_EXCEEDED, "上传文件超过大小限制"));
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

    // 全局日期格式解析失败时抛出 DateTimeParseException，属请求体格式问题而非系统故障。
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
    ResponseEntity<ApiResponse<Void>> handleAccessDenied(
            AuthorizationDeniedException exception,
            HttpServletRequest request
    ) {
        // Spring Security 的异常消息恒为 "Access Denied"，不能靠消息里的权限码判断；
        // 改为按请求面判定：管理面或读取接口的拒绝保持 WARN，个人写能力缺口降为 DEBUG。
        if (isExpectedCapabilityDenial(request)) {
            log.debug("权限不足(能力类): method={}, path={}", request.getMethod(), request.getRequestURI());
        } else {
            log.warn("权限不足: method={}, path={}, message={}",
                    request.getMethod(), request.getRequestURI(), exception.getMessage());
        }
        return ResponseEntity.status(HttpStatus.FORBIDDEN)
                .body(ApiResponse.error(ErrorCode.FORBIDDEN, "权限不足，无法执行此操作"));
    }

    private boolean isExpectedCapabilityDenial(HttpServletRequest request) {
        String path = request.getRequestURI();
        if (path == null || path.contains("/admin/")) {
            return false;
        }
        // 读取接口的 403 是权限回归信号，必须保留 WARN。
        if ("GET".equalsIgnoreCase(request.getMethod())
                || "HEAD".equalsIgnoreCase(request.getMethod())) {
            return false;
        }
        return path.startsWith("/api/v1/me")
                || path.startsWith("/api/v1/preferences")
                || path.startsWith("/api/v1/files")
                || path.startsWith("/api/v1/reader")
                || path.startsWith("/api/v1/music")
                || path.startsWith("/api/v1/video")
                || path.startsWith("/api/v1/photos")
                || path.startsWith("/api/v1/backdrops")
                || path.startsWith("/api/v1/notifications")
                || path.startsWith("/api/v1/weather");
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
     *
     * <p>非客户端断开的 IO 故障必须落到 5xx：静默返回会让请求以 HTTP 200 加空响应体
     * 正常结束，前端把故障当成成功并在反序列化处报错。</p>
     */
    @ExceptionHandler(IOException.class)
    void handleIoException(IOException exception, HttpServletResponse response) throws IOException {
        if (isClientDisconnect(exception)) {
            log.debug("流式响应已中断: {}", exception.getMessage());
            return;
        }
        log.error("未处理的 IO 异常", exception);
        writeInternalError(response);
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
        writeInternalError(response);
    }

    /**
     * 写出统一的 5xx 内部错误响应。
     *
     * <p>响应已提交时不能再改状态码；流式接口预设媒体 Content-Type 时写 JSON 会触发
     * 转换器异常，两种情况都只记日志并保持既有响应，不再追加错误体。</p>
     */
    private void writeInternalError(HttpServletResponse response) throws IOException {
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
        byte[] body = JsonSupport.toJson(
                ApiResponse.error(ErrorCode.INTERNAL_ERROR, "系统繁忙，请稍后重试"))
                .getBytes(StandardCharsets.UTF_8);
        try {
            // 流式接口可能已经调用 getOutputStream；此时再取 getWriter 会抛
            // IllegalStateException 并吞掉原始异常。统一走输出流写出字节。
            response.getOutputStream().write(body);
        } catch (IllegalStateException exception) {
            // 已有 writer 的极端场景回退到字符流，保证错误体仍可交付。
            response.getWriter().write(new String(body, StandardCharsets.UTF_8));
        }
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
