package com.omninest.common.config;

import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;
import org.springframework.web.filter.CorsFilter;

/**
 * API 与 Worker 共用的跨域访问配置。
 */
@Configuration
@RequiredArgsConstructor
public class CorsConfig {

    /**
     * 跨源请求允许携带的请求头白名单。
     *
     * 控制器经 @RequestHeader 消费的非 CORS 简单头必须同步登记于此，
     * 否则浏览器端跨源调用（如分享落地页的两步会话头）会在预检被拒，
     * 前端表现为 NETWORK_ERROR。回归契约见 CorsHeadersContractTest。
     */
    static final List<String> ALLOWED_HEADERS = List.of(
            "Authorization",
            "Content-Type",
            "Range",
            "X-CSRF-TOKEN",
            "X-Client-Platform",
            "X-Device-Id",
            "X-Device-Name",
            "X-Request-Id",
            "X-Requested-With",
            "X-Setup-Token",
            "X-OmniNest-Share-Session"
    );

    private final SecurityProperties securityProperties;

    @Bean
    public FilterRegistrationBean<CorsFilter> corsFilterRegistrationBean() {
        CorsConfiguration corsConfiguration = new CorsConfiguration();
        corsConfiguration.setAllowedOrigins(securityProperties.getAllowedOrigins());
        corsConfiguration.setAllowedMethods(List.of("GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"));
        corsConfiguration.setAllowedHeaders(ALLOWED_HEADERS);
        corsConfiguration.setExposedHeaders(List.of("Authorization", "X-RateLimit-Limit", "X-RateLimit-Remaining", "X-RateLimit-Reset"));
        corsConfiguration.setAllowCredentials(securityProperties.isAllowCredentials());
        corsConfiguration.setMaxAge(3600L);

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", corsConfiguration);

        FilterRegistrationBean<CorsFilter> registrationBean = new FilterRegistrationBean<>();
        registrationBean.setFilter(new CorsFilter(source));
        registrationBean.setOrder(Ordered.HIGHEST_PRECEDENCE);
        return registrationBean;
    }
}
