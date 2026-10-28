package com.omninest.common.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.core.convert.converter.Converter;
import org.springframework.http.HttpHeaders;
import org.springframework.security.authentication.AbstractAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * 登出请求的尽力 Bearer 解析。
 *
 * <p>有效令牌照常建立认证以按 sid 吊销会话；过期或无效令牌直接忽略，
 * 让 Controller 仍能幂等清理 Cookie 与刷新令牌。</p>
 *
 * @author OmniNest
 */
final class LogoutBearerTokenFilter extends OncePerRequestFilter {

    static final String LOGOUT_PATH = "/api/v1/auth/logout";
    private static final String TOKEN_USE_CLAIM = "token_use";
    private static final String ACCESS_TOKEN_USE = "access";

    private final JwtDecoder jwtDecoder;
    private final Converter<Jwt, ? extends AbstractAuthenticationToken> converter;

    LogoutBearerTokenFilter(
            JwtDecoder jwtDecoder,
            Converter<Jwt, ? extends AbstractAuthenticationToken> converter
    ) {
        this.jwtDecoder = jwtDecoder;
        this.converter = converter;
    }

    static boolean isLogoutRequest(HttpServletRequest request) {
        // 部分转发/测试场景 servletPath 为空串，必须兼容 requestURI。
        return request.getServletPath() != null && LOGOUT_PATH.equals(request.getServletPath())
                || request.getRequestURI() != null && request.getRequestURI().endsWith(LOGOUT_PATH);
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !isLogoutRequest(request);
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain
    ) throws ServletException, IOException {
        String header = request.getHeader(HttpHeaders.AUTHORIZATION);
        if (header != null && header.startsWith("Bearer ")) {
            try {
                Jwt jwt = jwtDecoder.decode(header.substring("Bearer ".length()));
                if (!ACCESS_TOKEN_USE.equals(jwt.getClaimAsString(TOKEN_USE_CLAIM))) {
                    // 只接受访问令牌：刷新令牌或挑战令牌不得注入 SecurityContext。
                    filterChain.doFilter(request, response);
                    return;
                }
                AbstractAuthenticationToken authentication = converter.convert(jwt);
                if (authentication != null) {
                    authentication.setDetails(
                            new WebAuthenticationDetailsSource().buildDetails(request));
                    SecurityContextHolder.getContext().setAuthentication(authentication);
                }
            } catch (JwtException | IllegalArgumentException ignored) {
                // 过期/无效凭据：登出仍需幂等成功并清 Cookie。
                SecurityContextHolder.clearContext();
            }
        }
        filterChain.doFilter(request, response);
    }
}
