package com.omninest.common.security;

import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 将令牌声明映射为系统权限编码。
 *
 * @author OmniNest
 */
public final class TokenAuthorityMapper {

    public static final String ACCESS_TOKEN_AUTHORITY = "TOKEN_ACCESS";
    private static final String ROLE_PREFIX = "ROLE_";

    private TokenAuthorityMapper() {
    }

    /**
     * 将访问令牌声明映射为去重且顺序稳定的权限集合。
     *
     * @param claims 令牌声明
     * @return 权限编码集合，非访问令牌返回空集合
     */
    public static Set<String> map(Map<String, Object> claims) {
        LinkedHashSet<String> authorities = new LinkedHashSet<>();
        if (claims == null || !"access".equals(stringValue(claims.get("token_use")))) {
            return authorities;
        }
        authorities.add(ACCESS_TOKEN_AUTHORITY);
        for (String role : claimValues(claims, "roles")) {
            String normalizedRole = normalize(role);
            if (!normalizedRole.isEmpty()) {
                authorities.add(toRoleAuthority(normalizedRole));
            }
        }
        String fallbackRole = normalize(stringValue(claims.get("role")));
        if (!fallbackRole.isEmpty()) {
            authorities.add(toRoleAuthority(fallbackRole));
        }
        for (String permission : claimValues(claims, "permissions")) {
            String normalizedPermission = normalize(permission);
            if (!normalizedPermission.isEmpty()) {
                authorities.add(normalizedPermission);
            }
        }
        return authorities;
    }

    private static List<String> claimValues(Map<String, Object> claims, String claimName) {
        Object value = claims.get(claimName);
        if (value instanceof Collection<?> collection) {
            return collection.stream()
                    .map(String::valueOf)
                    .toList();
        }
        if (value instanceof String text && !text.isBlank()) {
            return List.of(text);
        }
        return List.of();
    }

    private static String stringValue(Object value) {
        return value == null ? "" : String.valueOf(value);
    }

    private static String normalize(String value) {
        return value == null ? "" : value.trim();
    }

    private static String toRoleAuthority(String role) {
        return role.startsWith(ROLE_PREFIX) ? role : ROLE_PREFIX + role;
    }
}
