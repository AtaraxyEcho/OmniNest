package com.omninest.common.logging;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.UUID;
import java.util.regex.Pattern;
import org.slf4j.MDC;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * 请求 ID 追踪过滤器。
 * 生成或透传 X-Request-Id，写入 MDC 供日志使用。
 */
@Component
public class RequestIdFilter extends OncePerRequestFilter {

    private static final String REQUEST_ID_HEADER = "X-Request-Id";
    private static final String MDC_KEY = "requestId";
    /**
     * 请求 ID 允许的字符集：换行与控制字符一旦进入 MDC，就能伪造日志行结构，
     * 干扰按行解析的后台日志查看器。不匹配时一律换成新生成的 UUID。
     */
    private static final Pattern SAFE_REQUEST_ID = Pattern.compile("[A-Za-z0-9._-]{1,128}");

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        String requestId = normalizeRequestId(request.getHeader(REQUEST_ID_HEADER));
        MDC.put(MDC_KEY, requestId);
        response.setHeader(REQUEST_ID_HEADER, requestId);
        try {
            filterChain.doFilter(request, response);
        } finally {
            MDC.remove(MDC_KEY);
        }
    }

    private String normalizeRequestId(String rawRequestId) {
        if (rawRequestId == null || !SAFE_REQUEST_ID.matcher(rawRequestId).matches()) {
            return UUID.randomUUID().toString();
        }
        return rawRequestId;
    }
}
