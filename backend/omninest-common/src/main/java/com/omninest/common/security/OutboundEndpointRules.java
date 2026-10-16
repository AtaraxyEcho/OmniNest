package com.omninest.common.security;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import java.net.URI;
import java.util.Locale;

/**
 * 服务端主动出站到第三方接口的地址规则。
 *
 * <p>接口基址由超级管理员在配置中心维护（{@code system:config:manage} 只授予超级管理员），
 * 因此按自建端点档位放行环回与内网专用地址段——本机 sidecar 与内网反代是这类部署的正常形态；
 * 但任意本地、链路本地（含云元数据 169.254.0.0/16）、多播与保留地址段仍然拒绝，
 * 每次实际请求的协议、用户信息段与来源还必须与基址同源，防止路径拼接或上游跳转把请求带到别的主机。</p>
 *
 * <p>与外部存储端点守卫的差别：那里的地址由普通用户提交，因此默认只放行公网地址，
 * 访问内网需要部署级开关；这里的地址本身已是超级管理员的决定。</p>
 *
 * @author OmniNest
 */
public final class OutboundEndpointRules {

    private static final String GOOGLE_METADATA_HOST = "metadata.google.internal";
    private static final String GENERIC_METADATA_HOST = "metadata";

    private OutboundEndpointRules() {
    }

    /**
     * 解析并校验配置中心维护的接口基址。
     *
     * @param configuredBaseUrl 配置项原文
     * @return 校验通过的基址
     * @throws BusinessException 地址为空、格式非法、协议不支持或指向元数据服务
     */
    public static URI parseConfiguredBaseUrl(String configuredBaseUrl) {
        if (configuredBaseUrl == null || configuredBaseUrl.isBlank()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "外部服务地址未配置");
        }
        try {
            return requireHttpUri(URI.create(configuredBaseUrl.trim()), "外部服务地址");
        } catch (IllegalArgumentException exception) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "外部服务地址格式无效");
        }
    }

    /**
     * 校验实际请求地址仍停留在配置基址的协议、主机与端口内，并把基址按自建端点档位复核一次：
     * 环回与内网专用段放行（sidecar、内网反代是这类部署的正常形态），
     * 任意本地、链路本地（含云元数据段）、多播与保留段拒绝。
     *
     * @param configuredBaseUrl 配置项原文
     * @param target 实际要请求的完整地址
     * @param safeUrlValidator 地址解析校验器
     * @return 校验通过的请求地址
     * @throws BusinessException 请求地址协议非法、指向元数据服务、解析结果受限或已偏离基址
     */
    public static URI requireConfiguredEndpoint(
            String configuredBaseUrl,
            URI target,
            SafeUrlValidator safeUrlValidator
    ) {
        URI origin = parseConfiguredBaseUrl(configuredBaseUrl);
        requireHttpUri(target, "外部服务请求地址");
        if (!sameOrigin(origin, target)) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "外部服务请求地址偏离配置的基址");
        }
        safeUrlValidator.requireSelfHostedSafeHost(origin);
        return target;
    }

    /**
     * 校验请求地址指向代码内置的公网服务：按 DNS 解析结果拒绝环回、内网、链路本地与受限地址。
     *
     * @param target 实际要请求的完整地址
     * @param safeUrlValidator 地址解析校验器
     * @return 校验通过的请求地址
     * @throws BusinessException 请求地址协议非法或解析结果受限
     */
    public static URI requirePublicEndpoint(URI target, SafeUrlValidator safeUrlValidator) {
        requireHttpUri(target, "外部服务请求地址");
        safeUrlValidator.requireSafeHost(target);
        return target;
    }

    private static URI requireHttpUri(URI uri, String label) {
        if (uri == null) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, label + "不能为空");
        }
        String scheme = normalizedScheme(uri);
        if (!"http".equals(scheme) && !"https".equals(scheme)) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, label + "仅支持 HTTP 和 HTTPS 协议");
        }
        if (uri.getUserInfo() != null && !uri.getUserInfo().isBlank()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, label + "不允许携带用户信息");
        }
        String host = normalizedHost(uri);
        if (host.isEmpty()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, label + "缺少主机名");
        }
        if (isMetadataHost(host)) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, label + "不能指向元数据服务");
        }
        return uri;
    }

    private static boolean sameOrigin(URI left, URI right) {
        return normalizedScheme(left).equals(normalizedScheme(right))
                && normalizedHost(left).equals(normalizedHost(right))
                && effectivePort(left) == effectivePort(right);
    }

    private static int effectivePort(URI uri) {
        if (uri.getPort() >= 0) {
            return uri.getPort();
        }
        return "https".equals(normalizedScheme(uri)) ? 443 : 80;
    }

    private static String normalizedScheme(URI uri) {
        return uri.getScheme() == null ? "" : uri.getScheme().toLowerCase(Locale.ROOT);
    }

    private static String normalizedHost(URI uri) {
        if (uri.getHost() == null) {
            return "";
        }
        String host = uri.getHost().toLowerCase(Locale.ROOT);
        if (host.startsWith("[") && host.endsWith("]")) {
            host = host.substring(1, host.length() - 1);
        }
        while (host.endsWith(".")) {
            host = host.substring(0, host.length() - 1);
        }
        return host;
    }

    private static boolean isMetadataHost(String host) {
        return GENERIC_METADATA_HOST.equals(host)
                || GOOGLE_METADATA_HOST.equals(host)
                || host.endsWith("." + GOOGLE_METADATA_HOST)
                || "169.254.169.254".equals(host);
    }
}
