package com.omninest.common.config;

import static org.assertj.core.api.Assertions.assertThat;

import jakarta.servlet.ServletException;
import java.io.IOException;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

class CorsConfigTest {

    @Test
    void setupPreflightAllowsSetupTokenHeader() throws ServletException, IOException {
        SecurityProperties securityProperties = new SecurityProperties();
        CorsConfig corsConfig = new CorsConfig(securityProperties);
        var corsFilter = corsConfig.corsFilterRegistrationBean().getFilter();
        var request = new MockHttpServletRequest("OPTIONS", "/api/v1/setup/super-admin");
        request.addHeader(HttpHeaders.ORIGIN, "http://localhost:3000");
        request.addHeader(HttpHeaders.ACCESS_CONTROL_REQUEST_METHOD, "POST");
        request.addHeader(HttpHeaders.ACCESS_CONTROL_REQUEST_HEADERS, "content-type,x-setup-token");
        var response = new MockHttpServletResponse();

        corsFilter.doFilter(request, response, new MockFilterChain());

        assertThat(response.getStatus()).isEqualTo(200);
        assertThat(response.getHeader(HttpHeaders.ACCESS_CONTROL_ALLOW_HEADERS))
                .containsIgnoringCase("x-setup-token");
    }
}
