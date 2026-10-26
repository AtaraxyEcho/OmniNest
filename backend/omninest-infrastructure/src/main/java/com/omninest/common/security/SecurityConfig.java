package com.omninest.common.security;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.config.SecurityProperties;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.json.JsonSupport;
import com.nimbusds.jose.jwk.source.ImmutableSecret;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import javax.crypto.spec.SecretKeySpec;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
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
import org.springframework.security.oauth2.server.resource.web.BearerTokenResolver;
import org.springframework.security.oauth2.server.resource.web.DefaultBearerTokenResolver;
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
        // 分享链接与 OAuth 回调由一次性 state/token 校验，不携带 Bearer。
        // /api/v1/s/** 显式枚举匿名可达的分享端点：accept 需要登录用户身份，
        // 不在本链（落入主链按 Bearer 鉴权），否则该端点永远 401。
        http.securityMatcher(
                        "/api/v1/public/**",
                        "/api/v1/s/*",
                        "/api/v1/s/*/authorize",
                        "/api/v1/s/*/preview",
                        "/api/v1/s/*/children",
                        "/share/**",
                        // 登录、注册、刷新与初始化本身不需要 Bearer；客户端残留的过期
                        // Authorization 头不能在这些端点上先被资源服务器打成 401。
                        "/api/v1/auth/login",
                        "/api/v1/auth/login/**",
                        "/api/v1/auth/register",
                        "/api/v1/auth/refresh",
                        "/api/v1/setup/**",
                        "/api/v1/app/version",
                        "/api/v1/external-connectors/*/oauth/callback",
                        // 播放会话流由查询串中的一次性播放令牌鉴权；浏览器残留的过期 Bearer
                        // 不应在 JWT 解码阶段把公开媒体请求打成 401。
                        "/api/v1/music/playback/sessions/*/stream"
                )
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
            SessionRevocationChecker sessionRevocationChecker,
            BearerTokenResolver bearerTokenResolver,
            LogoutBearerTokenFilter logoutBearerTokenFilter,
            @Value("${springdoc.api-docs.enabled:true}") boolean apiDocsEnabled
    ) throws Exception {
        http
                .csrf(AbstractHttpConfigurer::disable)
                .formLogin(AbstractHttpConfigurer::disable)
                .httpBasic(AbstractHttpConfigurer::disable)
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(authorize -> {
                    authorize
                        .requestMatchers("/actuator/health", "/actuator/health/**", "/actuator/info").permitAll()
                        // 指标/环境等其它 Actuator 端点含内部拓扑与 SQL 信息，只允许系统配置读权限
                        .requestMatchers("/actuator/**").hasAuthority(Permissions.SYSTEM_CONFIG_READ)
                        // 错误派发必须匿名可达，否则流式响应失败后二次 Access Denied 并掩盖真实异常
                        .requestMatchers("/error").permitAll()
                        // 托管的前端 SPA（分享链接的 Web 入口）：hash 路由仅需首页与静态资源匿名可达
                        .requestMatchers(
                                HttpMethod.GET,
                                "/",
                                "/index.html",
                                "/main.dart.js",
                                "/flutter.js",
                                "/flutter_bootstrap.js",
                                "/flutter_service_worker.js",
                                "/manifest.json",
                                "/favicon.png",
                                "/favicon.ico",
                                "/version.json",
                                // Web 端 drift 离线库经 Worker 无凭据拉取，必须匿名可达，
                                // 否则数据库无法初始化（壁纸库面板永久加载中等级联故障）。
                                "/drift_worker.js",
                                "/sqlite3.wasm"
                        ).permitAll()
                        // CSP 禁止内联脚本后，启动脚本与壳样式必须匿名可达
                        .requestMatchers("/js/**", "/css/**").permitAll()
                        .requestMatchers("/assets/**", "/icons/**", "/canvaskit/**").permitAll()
                        .requestMatchers("/api/v1/auth/**").permitAll()
                        .requestMatchers(HttpMethod.GET, "/api/v1/setup/status").permitAll()
                        .requestMatchers(HttpMethod.POST, "/api/v1/setup/super-admin").permitAll()
                        .requestMatchers(HttpMethod.POST, "/api/v1/setup/2fa/secret").permitAll()
                        .requestMatchers(HttpMethod.GET, "/setup").permitAll()
                        // 外部存储 OAuth 回调由浏览器从三方站点匿名回跳，带不上 Bearer 令牌；
                        // 该端点靠一次性 state 关联授权会话并定位账户，不暴露任何账户数据。
                        .requestMatchers(
                                HttpMethod.GET,
                                "/api/v1/external-connectors/*/oauth/callback"
                        ).permitAll()
                        .requestMatchers("/ws/**").permitAll();
                    if (apiDocsEnabled) {
                        authorize.requestMatchers(
                                "/swagger-ui/**",
                                "/swagger-ui.html",
                                "/v3/api-docs/**",
                                "/api-docs/**"
                        ).permitAll();
                    }
                    // 所有 admin 端点由 @PreAuthorize 注解控制，此处仅要求有效 token
                    authorize.anyRequest().hasAuthority(TokenAuthorityMapper.ACCESS_TOKEN_AUTHORITY);
                }
                )
                .exceptionHandling(exception -> exception
                        .authenticationEntryPoint((request, response, authException) ->
                                writeError(response, HttpServletResponse.SC_UNAUTHORIZED, ErrorCode.UNAUTHORIZED))
                        .accessDeniedHandler((request, response, accessDeniedException) ->
                                writeError(response, HttpServletResponse.SC_FORBIDDEN, ErrorCode.FORBIDDEN))
                )
                .oauth2ResourceServer(oauth2 -> oauth2
                        .bearerTokenResolver(bearerTokenResolver)
                        .jwt(jwt -> jwt.jwtAuthenticationConverter(jwtAuthenticationConverter()))
                )
                .addFilterBefore(logoutBearerTokenFilter, BearerTokenAuthenticationFilter.class)
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

    /**
     * 登出端点不交给资源服务器解析 Bearer：过期或无效令牌不能把幂等登出挡成 401。
     * 其他端点保持默认解析行为。
     */
    @Bean
    BearerTokenResolver bearerTokenResolver() {
        DefaultBearerTokenResolver delegate = new DefaultBearerTokenResolver();
        return request -> LogoutBearerTokenFilter.isLogoutRequest(request)
                ? null
                : delegate.resolve(request);
    }

    /**
     * 登出请求的尽力 Bearer 解析；有效令牌按 sid 吊销会话，过期/无效令牌被忽略。
     */
    @Bean
    LogoutBearerTokenFilter logoutBearerTokenFilter(JwtDecoder jwtDecoder) {
        return new LogoutBearerTokenFilter(jwtDecoder, jwtAuthenticationConverter());
    }

    /**
     * 该过滤器只作为安全链内的一环运行，禁止 Spring Boot 再把它注册成全局 Servlet Filter。
     */
    @Bean
    FilterRegistrationBean<LogoutBearerTokenFilter> logoutBearerTokenFilterRegistration(
            LogoutBearerTokenFilter logoutBearerTokenFilter
    ) {
        FilterRegistrationBean<LogoutBearerTokenFilter> registration =
                new FilterRegistrationBean<>(logoutBearerTokenFilter);
        registration.setEnabled(false);
        return registration;
    }

    @Bean
    PasswordEncoder passwordEncoder() {
        // 强度 12：仅影响新产生的哈希，存量 $2a$10 哈希仍可校验
        return new BCryptPasswordEncoder(12);
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
        response.getWriter().write(JsonSupport.toJson(ApiResponse.error(errorCode)));
    }
}
