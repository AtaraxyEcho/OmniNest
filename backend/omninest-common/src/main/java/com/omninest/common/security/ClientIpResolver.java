package com.omninest.common.security;

/**
 * 按可信代理边界解析客户端 IP。
 *
 * @author OmniNest
 */
public interface ClientIpResolver {

    /**
     * 解析请求的客户端 IP。
     *
     * @param remoteAddress 直接连接地址
     * @param forwardedFor X-Forwarded-For 请求头
     * @param realIp X-Real-IP 请求头
     * @return 可用于限流和审计的客户端 IP
     */
    String resolve(String remoteAddress, String forwardedFor, String realIp);
}
