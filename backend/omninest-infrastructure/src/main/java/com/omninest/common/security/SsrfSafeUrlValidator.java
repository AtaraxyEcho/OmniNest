package com.omninest.common.security;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import java.net.Inet4Address;
import java.net.Inet6Address;
import java.net.InetAddress;
import java.net.URI;
import java.net.UnknownHostException;
import java.util.Locale;
import org.springframework.stereotype.Component;

/**
 * SSRF 防护：验证 URL 是否指向安全的外部地址。
 * 阻止指向本地、内网、元数据服务的请求。
 *
 * @author OmniNest
 */
@Component
public final class SsrfSafeUrlValidator implements SafeUrlValidator {

    /**
     * 主机名解析器：生产用系统 DNS，测试可注入以固定公网/内网结果。
     */
    @FunctionalInterface
    interface HostResolver {
        InetAddress[] getAllByName(String host) throws UnknownHostException;
    }

    private final HostResolver hostResolver;

    public SsrfSafeUrlValidator() {
        this(InetAddress::getAllByName);
    }

    SsrfSafeUrlValidator(HostResolver hostResolver) {
        this.hostResolver = hostResolver;
    }

    /**
     * 验证 URL 的主机名和解析后的 IP 地址是否安全。
     *
     * @param uri 待验证的 URI
     * @throws BusinessException 如果地址指向本地或内网
     */
    @Override
    public void requireSafeHost(URI uri) {
        String host = uri.getHost();
        if (host == null || host.isBlank()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "URL 缺少主机名");
        }
        if (isReservedHostName(host)) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "URL 不能指向本地或内网地址");
        }
        try {
            InetAddress[] addresses = hostResolver.getAllByName(host);
            if (addresses.length == 0) {
                throw new BusinessException(ErrorCode.BAD_REQUEST, "URL 无法解析");
            }
            for (InetAddress address : addresses) {
                if (isBlockedAddress(address)) {
                    throw new BusinessException(ErrorCode.BAD_REQUEST, "URL 不能指向本地或内网地址");
                }
            }
        } catch (UnknownHostException exception) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "URL 无法解析");
        }
    }

    /**
     * 验证 URL 字符串是否安全（含 scheme 检查）。
     *
     * @param url 待验证的 URL 字符串
     * @throws BusinessException 如果 URL 不安全或格式不正确
     */
    @Override
    public void requireSafeHttpUrl(String url) {
        if (url == null || url.isBlank()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "URL 不能为空");
        }
        URI uri;
        try {
            uri = URI.create(url.trim());
        } catch (IllegalArgumentException exception) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "URL 格式不正确");
        }
        String scheme = uri.getScheme() == null ? "" : uri.getScheme().toLowerCase(Locale.ROOT);
        if (!"http".equals(scheme) && !"https".equals(scheme)) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "仅支持 HTTP 和 HTTPS 协议");
        }
        if (uri.getUserInfo() != null && !uri.getUserInfo().isBlank()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "URL 不允许携带用户信息");
        }
        requireSafeHost(uri);
    }

    private static boolean isReservedHostName(String host) {
        String normalized = host.toLowerCase(Locale.ROOT);
        return "localhost".equals(normalized)
                || normalized.endsWith(".localhost")
                || "metadata.google.internal".equals(normalized)
                || "metadata".equals(normalized);
    }

    private static boolean isBlockedAddress(InetAddress address) {
        if (address.isAnyLocalAddress()
                || address.isLoopbackAddress()
                || address.isLinkLocalAddress()
                || address.isSiteLocalAddress()
                || address.isMulticastAddress()) {
            return true;
        }
        if (address instanceof Inet6Address inet6Address) {
            byte[] bytes = inet6Address.getAddress();
            byte[] embeddedIpv4 = extractEmbeddedIpv4(bytes);
            if (embeddedIpv4 != null) {
                return isBlockedIpv4(embeddedIpv4);
            }
            int first = bytes[0] & 0xFF;
            // 唯一本地地址 fc00::/7，含 fd00::/8
            return (first & 0xFE) == 0xFC;
        }
        if (address instanceof Inet4Address inet4Address) {
            return isBlockedIpv4(inet4Address.getAddress());
        }
        return false;
    }

    /**
     * 提取 IPv6 中嵌入的 IPv4（IPv4-mapped、NAT64、6to4），无法提取时返回 null。
     */
    private static byte[] extractEmbeddedIpv4(byte[] bytes) {
        if (bytes.length != 16) {
            return null;
        }
        // IPv4-mapped IPv6：::ffff:a.b.c.d
        if (isZeroPrefix(bytes, 0, 10)
                && (bytes[10] & 0xFF) == 0xFF
                && (bytes[11] & 0xFF) == 0xFF) {
            return new byte[] {bytes[12], bytes[13], bytes[14], bytes[15]};
        }
        // NAT64 知名前缀 64:ff9b::/96
        if ((bytes[0] & 0xFF) == 0x00 && (bytes[1] & 0xFF) == 0x64
                && (bytes[2] & 0xFF) == 0xFF && (bytes[3] & 0xFF) == 0x9B
                && isZeroPrefix(bytes, 4, 8)) {
            return new byte[] {bytes[12], bytes[13], bytes[14], bytes[15]};
        }
        // 6to4 2002::/16：随后 4 字节为嵌入 IPv4
        if ((bytes[0] & 0xFF) == 0x20 && (bytes[1] & 0xFF) == 0x02) {
            return new byte[] {bytes[2], bytes[3], bytes[4], bytes[5]};
        }
        return null;
    }

    private static boolean isZeroPrefix(byte[] bytes, int from, int length) {
        for (int index = from; index < from + length; index++) {
            if (bytes[index] != 0) {
                return false;
            }
        }
        return true;
    }

    private static boolean isBlockedIpv4(byte[] bytes) {
        int first = bytes[0] & 0xFF;
        int second = bytes[1] & 0xFF;
        int third = bytes[2] & 0xFF;
        return first == 0
                || first == 10
                || first == 127
                || (first == 100 && second >= 64 && second <= 127)
                || (first == 169 && second == 254)
                || (first == 172 && second >= 16 && second <= 31)
                || (first == 192 && second == 168)
                || (first == 192 && second == 0 && third == 0)
                || (first == 192 && second == 88 && third == 99)
                || (first == 198 && (second == 18 || second == 19))
                || (first == 198 && second == 51 && third == 100)
                || (first == 203 && second == 0 && third == 113);
    }
}
