package com.omninest.modules.music.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.SafeUrlValidator;
import java.net.Inet4Address;
import java.net.Inet6Address;
import java.net.InetAddress;
import java.net.URI;
import java.net.UnknownHostException;
import java.util.Locale;
import java.util.Optional;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

/**
 * 校验在线音乐播放源，并处理平台内网端点及代理 Fake-IP 的受限授权。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class MusicOnlineSourceUrlPolicy {
    private static final String GOOGLE_METADATA_HOST = "metadata.google.internal";
    private static final String GENERIC_METADATA_HOST = "metadata";

    private final SafeUrlValidator safeUrlValidator;
    private final MusicRuntimeConfigService configService;
    private final MusicHostAddressResolver hostAddressResolver;

    /**
     * 校验在线音乐播放 URL 是否可由流网关访问。
     *
     * @param sourcePlatform 播放源所属平台
     * @param uri 待访问的播放源 URI
     * @throws BusinessException URL 格式非法、目标危险或内网端点未经配置授权时抛出
     */
    public void requireAllowed(String sourcePlatform, URI uri) {
        requireHttpUri(uri);
        String host = normalizedHost(uri);
        if (isMetadataHost(host)) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "音乐播放 URL 不能指向元数据服务");
        }
        try {
            safeUrlValidator.requireSafeHttpUrl(uri.toString());
            return;
        } catch (BusinessException exception) {
            if (isTrustedPlatformOrigin(sourcePlatform, uri)) {
                requireTrustedHostSafe(uri);
                log.debug("允许访问已配置的音乐平台端点: platform={}, host={}, port={}",
                        sourcePlatform, host, effectivePort(uri));
                return;
            }
            if (isTrustedPlaybackHost(sourcePlatform, host) && isProxyFakeIpResolution(host)) {
                log.debug("允许访问音乐平台官方 CDN 的代理 Fake-IP: platform={}, host={}",
                        sourcePlatform, host);
                return;
            }
            throw exception;
        }
    }

    private void requireHttpUri(URI uri) {
        if (uri == null) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "音乐播放 URL 不能为空");
        }
        String scheme = normalizedScheme(uri);
        if (!"http".equals(scheme) && !"https".equals(scheme)) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "音乐播放仅支持 HTTP 和 HTTPS 协议");
        }
        if (uri.getUserInfo() != null && !uri.getUserInfo().isBlank()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "音乐播放 URL 不允许携带用户信息");
        }
        if (normalizedHost(uri).isBlank()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "音乐播放 URL 缺少主机名");
        }
    }

    private boolean isTrustedPlatformOrigin(String sourcePlatform, URI candidate) {
        return configService.trustedPlatformUrls(sourcePlatform).stream()
                .map(this::parseConfiguredUri)
                .flatMap(Optional::stream)
                .anyMatch(configured -> sameOrigin(candidate, configured));
    }

    private boolean isTrustedPlaybackHost(String sourcePlatform, String host) {
        return configService.trustedPlaybackHostSuffixes(sourcePlatform).stream()
                .anyMatch(suffix -> host.equals(suffix) || host.endsWith("." + suffix));
    }

    private Optional<URI> parseConfiguredUri(String value) {
        if (value == null || value.isBlank()) {
            return Optional.empty();
        }
        try {
            URI uri = URI.create(value.trim());
            String scheme = normalizedScheme(uri);
            if (("http".equals(scheme) || "https".equals(scheme)) && !normalizedHost(uri).isBlank()) {
                return Optional.of(uri);
            }
            return Optional.empty();
        } catch (IllegalArgumentException exception) {
            return Optional.empty();
        }
    }

    private boolean sameOrigin(URI left, URI right) {
        return normalizedScheme(left).equals(normalizedScheme(right))
                && normalizedHost(left).equals(normalizedHost(right))
                && effectivePort(left) == effectivePort(right);
    }

    private void requireTrustedHostSafe(URI uri) {
        String host = normalizedHost(uri);
        try {
            InetAddress[] addresses = hostAddressResolver.resolve(host);
            if (addresses.length == 0) {
                throw new BusinessException(ErrorCode.BAD_REQUEST, "音乐播放 URL 无法解析");
            }
            for (InetAddress address : addresses) {
                if (address.isAnyLocalAddress()
                        || address.isLinkLocalAddress()
                        || address.isMulticastAddress()) {
                    throw new BusinessException(ErrorCode.BAD_REQUEST, "音乐播放 URL 指向禁止访问的地址");
                }
            }
        } catch (UnknownHostException exception) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "音乐播放 URL 无法解析");
        }
    }

    private boolean isProxyFakeIpResolution(String host) {
        try {
            InetAddress[] addresses = hostAddressResolver.resolve(host);
            boolean hasFakeIpv4 = false;
            for (InetAddress address : addresses) {
                if (isBenchmarkFakeIpv4(address)) {
                    hasFakeIpv4 = true;
                    break;
                }
            }
            if (!hasFakeIpv4) {
                return false;
            }
            for (InetAddress address : addresses) {
                // 只有 Fake-IP 段可以被跳过；IPv6 ULA 与其余内网段必须走拦截判定。
                if (isBenchmarkFakeIpv4(address)) {
                    continue;
                }
                if (isBlockedAddress(address)) {
                    return false;
                }
            }
            return true;
        } catch (UnknownHostException exception) {
            return false;
        }
    }

    private boolean isBenchmarkFakeIpv4(InetAddress address) {
        if (!(address instanceof Inet4Address inet4Address)) {
            return false;
        }
        byte[] bytes = inet4Address.getAddress();
        int first = bytes[0] & 0xFF;
        int second = bytes[1] & 0xFF;
        return first == 198 && (second == 18 || second == 19);
    }

    private boolean isUniqueLocalIpv6(InetAddress address) {
        if (!(address instanceof Inet6Address inet6Address)) {
            return false;
        }
        int first = inet6Address.getAddress()[0] & 0xFF;
        return (first & 0xFE) == 0xFC;
    }

    private boolean isBlockedAddress(InetAddress address) {
        if (address.isAnyLocalAddress()
                || address.isLoopbackAddress()
                || address.isLinkLocalAddress()
                || address.isSiteLocalAddress()
                || address.isMulticastAddress()) {
            return true;
        }
        if (address instanceof Inet4Address inet4Address) {
            byte[] bytes = inet4Address.getAddress();
            int first = bytes[0] & 0xFF;
            int second = bytes[1] & 0xFF;
            return first == 0
                    || first == 10
                    || first == 127
                    || (first == 100 && second >= 64 && second <= 127)
                    || (first == 169 && second == 254)
                    || (first == 172 && second >= 16 && second <= 31)
                    || (first == 192 && second == 168);
        }
        return isUniqueLocalIpv6(address);
    }

    private boolean isMetadataHost(String host) {
        return GENERIC_METADATA_HOST.equals(host)
                || GOOGLE_METADATA_HOST.equals(host)
                || host.endsWith("." + GOOGLE_METADATA_HOST)
                || "169.254.169.254".equals(host);
    }

    private String normalizedScheme(URI uri) {
        return uri.getScheme() == null ? "" : uri.getScheme().toLowerCase(Locale.ROOT);
    }

    private String normalizedHost(URI uri) {
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

    private int effectivePort(URI uri) {
        if (uri.getPort() >= 0) {
            return uri.getPort();
        }
        return "https".equals(normalizedScheme(uri)) ? 443 : 80;
    }
}
