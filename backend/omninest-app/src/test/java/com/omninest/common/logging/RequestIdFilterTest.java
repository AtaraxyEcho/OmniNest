package com.omninest.common.logging;

import static org.assertj.core.api.Assertions.assertThat;

import java.io.IOException;
import java.util.UUID;
import jakarta.servlet.ServletException;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

class RequestIdFilterTest {

    private final RequestIdFilter filter = new RequestIdFilter();

    @Test
    @DisplayName("请求无 X-Request-Id 时自动生成并写入响应头")
    void generatesRequestIdWhenAbsent() throws ServletException, IOException {
        MockHttpServletRequest request = new MockHttpServletRequest();
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilterInternal(request, response, (req, resp) -> {});

        String requestId = response.getHeader("X-Request-Id");
        assertThat(requestId).isNotBlank();
        assertThat(requestId).hasSize(36);
    }

    @Test
    @DisplayName("请求已有 X-Request-Id 时透传")
    void passesThroughExistingRequestId() throws ServletException, IOException {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("X-Request-Id", "existing-id-123");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilterInternal(request, response, (req, resp) -> {});

        assertThat(response.getHeader("X-Request-Id")).isEqualTo("existing-id-123");
    }

    @Test
    @DisplayName("X-Request-Id 含控制字符时替换为新生成的 UUID")
    void replacesRequestIdWithControlCharacters() throws ServletException, IOException {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("X-Request-Id", "abc\r\n2026-10-17 00:00:00 INFO 伪造日志行");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilterInternal(request, response, (req, resp) -> {});

        String requestId = response.getHeader("X-Request-Id");
        assertThat(requestId).doesNotContain("\r", "\n");
        assertThat(UUID.fromString(requestId)).isNotNull();
    }

    @Test
    @DisplayName("X-Request-Id 为空白时替换为新生成的 UUID")
    void replacesBlankRequestId() throws ServletException, IOException {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("X-Request-Id", "   ");
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter.doFilterInternal(request, response, (req, resp) -> {});

        String requestId = response.getHeader("X-Request-Id");
        assertThat(requestId).isNotEqualTo("   ");
        assertThat(UUID.fromString(requestId)).isNotNull();
    }
}
