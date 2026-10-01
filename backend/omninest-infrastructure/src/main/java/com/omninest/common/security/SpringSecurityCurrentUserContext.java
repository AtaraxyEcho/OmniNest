package com.omninest.common.security;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;
import org.springframework.security.authentication.AnonymousAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Component;

/**
 * 基于 Spring Security 的当前认证用户访问实现。
 *
 * @author OmniNest
 */
@Component
public class SpringSecurityCurrentUserContext implements CurrentUserContext {

    /**
     * 从 Spring Security 上下文解析当前认证用户。
     *
     * @return 当前认证用户信息
     */
    @Override
    public CurrentUser requireCurrentUser() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null
                || !authentication.isAuthenticated()
                || authentication instanceof AnonymousAuthenticationToken) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "未认证");
        }
        if (authentication instanceof JwtAuthenticationToken jwtAuthenticationToken) {
            return fromJwt(jwtAuthenticationToken.getToken());
        }
        if (authentication.getPrincipal() instanceof Jwt jwt) {
            return fromJwt(jwt);
        }
        throw new BusinessException(ErrorCode.UNAUTHORIZED, "登录凭证无效");
    }

    /**
     * 从 Spring Security 上下文解析当前认证用户标识。
     *
     * @return 当前用户标识
     */
    @Override
    public UUID requireCurrentUserId() {
        return requireCurrentUser().userId();
    }

    /**
     * 从当前访问令牌的 sid claim 解析会话标识，供“当前会话”标记等展示场景。
     */
    @Override
    public UUID currentSessionId() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        Jwt jwt = null;
        if (authentication instanceof JwtAuthenticationToken jwtAuthenticationToken) {
            jwt = jwtAuthenticationToken.getToken();
        } else if (authentication != null && authentication.getPrincipal() instanceof Jwt principalJwt) {
            jwt = principalJwt;
        }
        if (jwt == null) {
            return null;
        }
        try {
            return UUID.fromString(jwt.getClaimAsString("sid"));
        } catch (RuntimeException ex) {
            return null;
        }
    }

    private CurrentUser fromJwt(Jwt jwt) {
        UUID userId = resolveUserId(jwt);
        return new CurrentUser(
                userId,
                jwt.getSubject(),
                normalize(jwt.getClaimAsString("username"), userId.toString()),
                claimValues(jwt, "permissions"),
                claimValues(jwt, "roles")
        );
    }

    private UUID resolveUserId(Jwt jwt) {
        try {
            return UUID.fromString(jwt.getSubject());
        } catch (RuntimeException ex) {
            throw new BusinessException(ErrorCode.UNAUTHORIZED, "登录凭证无效");
        }
    }

    private Set<String> claimValues(Jwt jwt, String claimName) {
        Object value = jwt.getClaims().get(claimName);
        if (value instanceof Collection<?> collection) {
            return collection.stream()
                    .map(String::valueOf)
                    .map(String::trim)
                    .filter(text -> !text.isEmpty())
                    .collect(Collectors.toCollection(LinkedHashSet::new));
        }
        if (value instanceof String text && !text.isBlank()) {
            return new LinkedHashSet<>(List.of(text.trim()));
        }
        return Set.of();
    }

    private String normalize(String value, String fallback) {
        if (value == null || value.isBlank()) {
            return fallback;
        }
        return value.trim();
    }
}
