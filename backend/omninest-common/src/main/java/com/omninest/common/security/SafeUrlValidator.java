package com.omninest.common.security;

import java.net.URI;

/**
 * 校验外部 URL 是否满足服务端请求安全约束。
 *
 * @author OmniNest
 */
public interface SafeUrlValidator {

    /**
     * 校验 URI 的主机名及其解析地址是否允许访问。
     *
     * @param uri 待校验的 URI
     */
    void requireSafeHost(URI uri);

    /**
     * 校验 URI 的主机名及其解析地址是否允许访问，可选择放行内网专用地址段。
     * 供部署级开关显式允许连接内网自托管存储；环回、链路本地与受限地址仍然拒绝。
     *
     * @param uri 待校验的 URI
     * @param allowSiteLocal 是否允许 RFC1918 与 IPv6 唯一本地地址
     */
    void requireSafeHost(URI uri, boolean allowSiteLocal);

    /**
     * 校验超级管理员自建的常驻服务端点：放行环回与内网专用地址段，
     * 因为 sidecar 与内网反代是这类部署的正常形态；任意本地、链路本地、多播、
     * 受限地址段与云元数据主机名在任何模式下都拒绝。
     *
     * @param uri 待校验的 URI
     */
    void requireSelfHostedSafeHost(URI uri);

    /**
     * 校验 HTTP 或 HTTPS URL 是否允许访问。
     *
     * @param url 待校验的 URL
     */
    void requireSafeHttpUrl(String url);
}
