package com.omninest.common.error;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import com.omninest.common.enums.ErrorCode;
import org.assertj.core.api.Assertions;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.web.HttpRequestMethodNotSupportedException;
import org.springframework.web.context.request.async.AsyncRequestNotUsableException;
import org.springframework.web.servlet.NoHandlerFoundException;
import org.springframework.web.servlet.resource.NoResourceFoundException;

/**
 * 全局异常响应映射测试。
 *
 * @author Notask Flow Team
 */
class GlobalExceptionHandlerTest {

    private final GlobalExceptionHandler handler = new GlobalExceptionHandler();

    @Test
    @DisplayName("运行依赖不可用返回 503")
    void handleDependencyUnavailableReturns503() {
        BusinessException exception = new BusinessException(
                ErrorCode.DEPENDENCY_UNAVAILABLE,
                "依赖服务不可用"
        );

        var response = handler.handleBusiness(exception);

        Assertions.assertThat(response.getStatusCode()).isEqualTo(HttpStatus.SERVICE_UNAVAILABLE);
        Assertions.assertThat(response.getBody().getCode())
                .isEqualTo(ErrorCode.DEPENDENCY_UNAVAILABLE.getCode());
    }

    @Test
    @DisplayName("HttpRequestMethodNotSupportedException 返回 405")
    void handleMethodNotSupported_returns405() throws HttpRequestMethodNotSupportedException {
        var exception = new HttpRequestMethodNotSupportedException("PATCH");

        var response = handler.handleMethodNotSupported(exception);

        Assertions.assertThat(response.getStatusCode()).isEqualTo(HttpStatus.METHOD_NOT_ALLOWED);
        Assertions.assertThat(response.getBody().getCode()).isEqualTo(ErrorCode.BAD_REQUEST.getCode());
    }

    @Test
    @DisplayName("NoHandlerFoundException 返回 404")
    void handleNoHandlerFound_returns404() {
        var exception = new NoHandlerFoundException("GET", "/api/v1/unknown", null);

        var response = handler.handleNoHandlerFound(exception);

        Assertions.assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        Assertions.assertThat(response.getBody().getCode()).isEqualTo(ErrorCode.NOT_FOUND.getCode());
    }

    @Test
    @DisplayName("NoResourceFoundException 返回 404")
    void handleNoResourceFound_returns404() {
        var exception = new NoResourceFoundException(
                HttpMethod.GET,
                "api/v1/unknown",
                "/api/v1/unknown"
        );

        var response = handler.handleNoResourceFound(exception);

        Assertions.assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NOT_FOUND);
        Assertions.assertThat(response.getBody().getCode()).isEqualTo(ErrorCode.NOT_FOUND.getCode());
    }

    @Test
    @DisplayName("非 API 路径 404 降为 DEBUG，API 路径保持 WARN")
    void logsUnknownPathByPathPrefix() {
        Logger logger = (Logger) LoggerFactory.getLogger(GlobalExceptionHandler.class);
        Level originalLevel = logger.getLevel();
        ListAppender<ILoggingEvent> appender = new ListAppender<>();
        appender.start();
        logger.setLevel(Level.DEBUG);
        logger.addAppender(appender);
        try {
            handler.handleNoResourceFound(
                    new NoResourceFoundException(HttpMethod.GET, "index.html", "/index.html"));
            handler.handleNoResourceFound(
                    new NoResourceFoundException(HttpMethod.GET, "api/v1/unknown", "/api/v1/unknown"));
            handler.handleNoHandlerFound(new NoHandlerFoundException("GET", "/main.dart.js", null));

            Assertions.assertThat(appender.list).hasSize(3);
            Assertions.assertThat(appender.list.get(0).getLevel()).isEqualTo(Level.DEBUG);
            Assertions.assertThat(appender.list.get(1).getLevel()).isEqualTo(Level.WARN);
            Assertions.assertThat(appender.list.get(2).getLevel()).isEqualTo(Level.DEBUG);
        } finally {
            logger.detachAppender(appender);
            logger.setLevel(originalLevel);
        }
    }

    @Test
    @DisplayName("客户端断开异步请求时不再生成错误响应")
    void handleAsyncRequestNotUsable_doesNotWriteResponse() {
        AsyncRequestNotUsableException exception =
                new AsyncRequestNotUsableException("客户端已断开");

        Assertions.assertThatCode(() -> handler.handleAsyncRequestNotUsable(exception))
                .doesNotThrowAnyException();
    }
}
