package com.omninest.common.security;

import com.alibaba.fastjson2.JSON;
import com.nimbusds.jose.jwk.source.ImmutableSecret;
import com.omninest.common.api.ApiResponse;
import com.omninest.common.config.SecurityProperties;
import com.omninest.common.enums.ErrorCode;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.core.annotation.Order;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.convert.converter.Converter;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.AbstractAuthenticationToken;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.oauth2.jose.jws.MacAlgorithm;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtEncoder;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.oauth2.jwt.NimbusJwtEncoder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter;
import org.springframework.security.oauth2.server.resource.web.authentication.BearerTokenAuthenticationFilter;
import org.springframework.security.web.SecurityFilterChain;

/**
 * 配置 JWT、密码编码和 API 角色的 HTTP 安全链。
 *
 * @author OmniNest
 */
@Configuration
@EnableMethodSecurity
public class SecurityConfig {

    /**
     * 公开内容独立过滤链：分享与公开端点不解析 Bearer 凭据。
     *
     * <p>oauth2ResourceServer 对任何携带 Authorization 头的请求强制解码，
     * 浏览器残留的过期令牌会让 permitAll 的公开端点也在认证阶段返回 401
     * （认证失败先于授权判定）；本链不挂 JWT 解码，访客无凭据亦可访问。</p>
     */
    @Bean
    @Order(0)
    @ConditionalOnProperty(
            prefix = "omninest.runtime",
            name = "role",
            havingValue = "api",
            matchIfMissing = true
    )
    SecurityFilterChain publicContentFilterChain(HttpSecurity http) throws Exception {
        http.securityMatcher("/api/v1/public/**", "/api/v1/s/**")
                .csrf(AbstractHttpConfigurer::disable)
                .formLogin(AbstractHttpConfigurer::disable)
                .httpBasic(AbstractHttpConfigurer::disable)
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(authorize -> authorize.anyRequest().permitAll());
        return http.build();
    }

    @Bean
    @Order(1)
    @ConditionalOnProperty(
            prefix = "omninest.runtime",
            name = "role",
            havingValue = "api",
            matchIfMissing = true
    )
    SecurityFilterChain securityFilterChain(
            HttpSecurity http,
            SessionRevocationChecker sessionRevocationChecker
    ) throws Exception {
        http
                .csrf(AbstractHttpConfigurer::disable)
                .formLogin(AbstractHttpConfigurer::disable)
                .httpBasic(AbstractHttpConfigurer::disable)
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(authorize -> authorize
                        .requestMatchers("/actuator/health", "/actuator/info").permitAll()
                        // 托管的前端 SPA（分享链接的 Web 入口）：hash 路由仅需首页与静态资源匿名可达
                        .requestMatchers(
                                HttpMethod.GET,
                                "/",
                                "/share.html",
                                "/index.html",
                                "/main.dart.js",
                                "/flutter.js",
                                "/flutter_bootstrap.js",
                                "/flutter_service_worker.js",
                                "/manifest.json",
                                "/favicon.png",
                                "/favicon.ico",
                                "/version.json"
                        ).permitAll()
                        .requestMatchers("/assets/**", "/icons/**", "/canvaskit/**").permitAll()
                        .requestMatchers("/api/v1/auth/**").permitAll()
                        .requestMatchers(HttpMethod.GET, "/api/v1/setup/status").permitAll()
                        .requestMatchers(HttpMethod.POST, "/api/v1/setup/super-admin").permitAll()
                        .requestMatchers(HttpMethod.GET, "/setup").permitAll()
                        .requestMatchers(HttpMethod.GET, "/api/v1/music/playback/sessions/*/stream").permitAll()
                        .requestMatchers(HttpMethod.HEAD, "/api/v1/music/playback/sessions/*/stream").permitAll()
                        .requestMatchers("/ws/**").permitAll()
                        .requestMatchers(
                                "/swagger-ui/**",
                                "/swagger-ui.html",
                                "/v3/api-docs/**",
                                "/api-docs/**"
                        ).permitAll()
                        // 所有 admin 端点由 @PreAuthorize 注解控制，此处仅要求有效 token
                        .anyRequest().hasAuthority(TokenAuthorityMapper.ACCESS_TOKEN_AUTHORITY)
                )
                .exceptionHandling(exception -> exception
                        .authenticationEntryPoint((request, response, authException) ->
                                writeError(response, HttpServletResponse.SC_UNAUTHORIZED, ErrorCode.UNAUTHORIZED))
                        .accessDeniedHandler((request, response, accessDeniedException) ->
                                writeError(response, HttpServletResponse.SC_FORBIDDEN, ErrorCode.FORBIDDEN))
                )
                .oauth2ResourceServer(oauth2 -> oauth2.jwt(jwt ->
                        jwt.jwtAuthenticationConverter(jwtAuthenticationConverter())
                ))
                .addFilterAfter(
                        new SessionRevocationFilter(sessionRevocationChecker),
                        BearerTokenAuthenticationFilter.class
                );
        return http.build();
    }

    @Bean
    JwtAuthorityConverter jwtAuthorityConverter() {
        return new JwtAuthorityConverter();
    }

    @Bean
    Converter<Jwt, ? extends AbstractAuthenticationToken> jwtAuthenticationConverter() {
        JwtAuthenticationConverter converter = new JwtAuthenticationConverter();
        converter.setJwtGrantedAuthoritiesConverter(jwtAuthorityConverter());
        return converter;
    }

    @Bean
    PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    @Bean
    JwtEncoder jwtEncoder(SecurityProperties securityProperties) {
        return new NimbusJwtEncoder(new ImmutableSecret<>(jwtSecret(securityProperties)));
    }

    @Bean
    JwtDecoder jwtDecoder(SecurityProperties securityProperties) {
        return NimbusJwtDecoder.withSecretKey(jwtSecret(securityProperties))
                .macAlgorithm(MacAlgorithm.HS256)
                .build();
    }

    private SecretKeySpec jwtSecret(SecurityProperties securityProperties) {
        byte[] secret = securityProperties.getJwtSecret().getBytes(StandardCharsets.UTF_8);
        return new SecretKeySpec(secret, "HmacSHA256");
    }

    private void writeError(HttpServletResponse response, int status, ErrorCode errorCode) throws IOException {
        response.setStatus(status);
        response.setCharacterEncoding(StandardCharsets.UTF_8.name());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.getWriter().write(JSON.toJSONString(ApiResponse.error(errorCode)));
    }
}
