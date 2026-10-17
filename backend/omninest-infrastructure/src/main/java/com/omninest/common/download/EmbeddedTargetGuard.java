package com.omninest.common.download;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.SafeUrlValidator;
import java.net.URI;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;

/**
 * 下载源内嵌对外地址的统一 SSRF 判定口径：磁力链接参数与种子文件字段共用同一套规则，
 * 避免同一条链路对同一个地址给出两种结论。
 *
 * @author OmniNest
 */
final class EmbeddedTargetGuard {

    private EmbeddedTargetGuard() {
    }

    /**
     * 校验会取回内容的地址（web seed）：按完整 HTTP 校验处理，包含名称解析与重定向前校验。
     *
     * @param validator 安全 URL 校验器
     * @param url 待校验地址
     */
    static void requireWebSeed(SafeUrlValidator validator, String url) {
        validator.requireSafeHttpUrl(url);
    }

    /**
     * 校验 tracker 地址：只拒绝字面 IP 的私有段。
     * tracker 随时可能宕机，把一次无效名称解析变成整条下载链路的失败并不合理；
     * 而字面内网 IP 没有任何合法用途，必须在这里拦住。
     *
     * @param validator 安全 URL 校验器
     * @param tracker 待校验地址
     */
    static void requireTracker(SafeUrlValidator validator, String tracker) {
        URI uri = parse(tracker, "tracker 地址不正确");
        String host = uri.getHost();
        if (host == null || !isLiteralAddress(host)) {
            return;
        }
        validator.requireSafeHost(uri);
    }

    /**
     * 只识别字面 IP，绝不触发名称解析：IPv6 段可带方括号或直接含冒号。
     */
    static boolean isLiteralAddress(String host) {
        String value = host.startsWith("[") && host.endsWith("]")
                ? host.substring(1, host.length() - 1)
                : host;
        if (value.indexOf(':') >= 0) {
            return value.matches("[0-9a-fA-F:.]+");
        }
        return value.matches("\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}");
    }

    /**
     * 解码磁力链接参数值。
     *
     * @param rawValue 原始参数值
     * @return 解码后的值
     */
    static String decodeParam(String rawValue) {
        try {
            return URLDecoder.decode(rawValue, StandardCharsets.UTF_8);
        } catch (IllegalArgumentException exception) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "磁力链接参数编码不正确");
        }
    }

    /**
     * 解析地址，失败时转换为业务错误。
     *
     * @param rawValue 原始地址
     * @param message 业务错误文案
     * @return 解析后的 URI
     */
    static URI parse(String rawValue, String message) {
        try {
            return URI.create(rawValue);
        } catch (IllegalArgumentException exception) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, message);
        }
    }
}
