package com.omninest.common.security;

import java.util.Collection;
import java.util.LinkedHashSet;
import org.springframework.core.convert.converter.Converter;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;

/**
 * 将通用令牌权限映射结果适配为 Spring Security 权限对象。
 *
 * @author OmniNest
 */
public class JwtAuthorityConverter implements Converter<Jwt, Collection<GrantedAuthority>> {

    /**
     * 转换 JWT 中的系统权限声明。
     *
     * @param jwt 已验证的 JWT
     * @return Spring Security 权限集合
     */
    @Override
    public Collection<GrantedAuthority> convert(Jwt jwt) {
        LinkedHashSet<GrantedAuthority> authorities = new LinkedHashSet<>();
        for (String authority : TokenAuthorityMapper.map(jwt.getClaims())) {
            authorities.add(new SimpleGrantedAuthority(authority));
        }
        return authorities;
    }
}
