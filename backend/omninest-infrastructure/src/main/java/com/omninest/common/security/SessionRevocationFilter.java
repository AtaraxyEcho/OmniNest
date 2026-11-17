package com.omninest.common.security;

import com.omninest.common.json.JsonSupport;
import com.omninest.common.api.ApiResponse;
import com.omninest.common.enums.ErrorCode;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.MediaType;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * 会话撤销过滤器，检查 JWT 中的 sid 是否已被撤销。
 * <p>
 * 位于 BearerTokenAuthenticationFilter 之后，利用已解析的 JWT 信息。
 * 命中撤销记录时返回 40101 错误码，前端据此提示"会话已在其他设备登录"。
 */
@Slf4j
@RequiredArgsConstructor
public class SessionRevocationFilter extends OncePerRequestFilter {

    private final SessionRevocationChecker revocationChecker;

    /**
     * 登出与刷新必须可通行：登出要幂等清 Cookie；刷新要能凭刷新令牌换掉
     * 因权限变更而陈旧的访问令牌，否则切割旧令牌的检查会把恢复入口一起挡死。
     */
    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String servletPath = request.getServletPath();
        if (isCredentialRotationPath(servletPath)) {
            return true;
        }
        return isCredentialRotationPath(request.getRequestURI());
    }

    private boolean isCredentialRotationPath(String path) {
        return path != null
                && (path.endsWith("/api/v1/auth/logout") || path.endsWith("/api/v1/auth/refresh"));
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
            HttpServletResponse response, FilterChain chain) throws ServletException, IOException {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth instanceof JwtAuthenticationToken jwtAuth) {
            Jwt jwt = jwtAuth.getToken();
            String sid = jwt.getClaimAsString("sid");
            String sub = jwt.getSubject();
            if (sid == null || sid.isBlank() || sub == null || sub.isBlank()) {
                log.warn("access token missing sid/sub, reject fail-closed");
                writeRevokedResponse(response);
                return;
            }
            try {
                UUID userId = UUID.fromString(sub);
                UUID sessionId = UUID.fromString(sid);
                if (revocationChecker.isRevoked(userId, sessionId)) {
                    log.info("session revoked: userId={}, sessionId={}", userId, sessionId);
                    writeRevokedResponse(response);
                    return;
                }
                if (revocationChecker.isTokenStale(userId, jwt.getIssuedAt())) {
                    log.info("access token stale after permission change: userId={}, sessionId={}",
                            userId, sessionId);
                    writeRevokedResponse(response);
                    return;
                }
            } catch (IllegalArgumentException exception) {
                log.warn("JWT sid/sub invalid, reject fail-closed: sid={}, sub={}", sid, sub);
                writeRevokedResponse(response);
                return;
            }
        }
        chain.doFilter(request, response);
    }

    private void writeRevokedResponse(HttpServletResponse response) throws IOException {
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setCharacterEncoding(StandardCharsets.UTF_8.name());
        response.getWriter().write(
                JsonSupport.toJson(ApiResponse.error(ErrorCode.UNAUTHORIZED, "会话已在其他设备登录")));
    }
}
