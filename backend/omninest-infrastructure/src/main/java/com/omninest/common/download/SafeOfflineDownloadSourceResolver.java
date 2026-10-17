package com.omninest.common.download;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.security.SafeUrlValidator;
import java.net.URI;
import java.util.Locale;
import java.util.Set;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/**
 * 基于安全 URL 校验器解析离线下载源。
 *
 * @author OmniNest
 */
@Component
@RequiredArgsConstructor
public class SafeOfflineDownloadSourceResolver implements OfflineDownloadSourceResolver {
    /**
     * 磁力链接里由下载器主动取回内容的字段（BEP 9 web seed）。
     */
    private static final Set<String> WEB_SEED_KEYS = Set.of("ws");

    /**
     * 磁力链接里的 tracker 字段（BEP 19 an、BEP 15 tr）。
     */
    private static final Set<String> TRACKER_KEYS = Set.of("an", "tr");

    private final SafeUrlValidator safeUrlValidator;

    /**
     * 将用户输入解析为受支持的下载源。
     *
     * @param sourceUri 下载源地址
     * @return 规范化后的下载源
     */
    @Override
    public ResolvedSource resolve(String sourceUri) {
        if (sourceUri == null || sourceUri.isBlank()) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "离线下载地址不能为空");
        }
        String normalized = sourceUri.trim();
        if (normalized.regionMatches(true, 0, "magnet:", 0, "magnet:".length())) {
            URI magnet = EmbeddedTargetGuard.parse(normalized, "磁力链接格式不正确");
            requireSafeMagnetTargets(magnet);
            return new ResolvedSource(SourceKind.MAGNET, magnet);
        }
        if (normalized.regionMatches(true, 0, "bt://", 0, "bt://".length())) {
            return resolveNested(normalized.substring("bt://".length()));
        }
        if (normalized.regionMatches(true, 0, "bt:", 0, "bt:".length())) {
            return resolveNested(normalized.substring("bt:".length()));
        }

        URI uri = EmbeddedTargetGuard.parse(normalized, "离线下载地址格式不正确");
        String scheme = uri.getScheme() == null ? "" : uri.getScheme().toLowerCase(Locale.ROOT);
        if (!"http".equals(scheme) && !"https".equals(scheme)) {
            throw new BusinessException(ErrorCode.BAD_REQUEST, "暂只支持 HTTP、HTTPS、BT 和磁力链");
        }
        safeUrlValidator.requireSafeHttpUrl(normalized);
        if (looksLikeTorrent(uri)) {
            return new ResolvedSource(SourceKind.TORRENT_FILE, uri);
        }
        return new ResolvedSource(SourceKind.HTTP, uri);
    }

    /**
     * 校验磁力链接内嵌的对外地址：提交时只做静态检查，真正发起请求的是下载器，
     * 因此内嵌的 web seed 与 tracker 必须在这里过一次闸门。
     */
    private void requireSafeMagnetTargets(URI magnet) {
        String rawQuery = rawQueryOf(magnet);
        if (rawQuery == null || rawQuery.isBlank()) {
            return;
        }
        for (String pair : rawQuery.split("&")) {
            int separator = pair.indexOf('=');
            if (separator <= 0) {
                continue;
            }
            String key = pair.substring(0, separator).toLowerCase(Locale.ROOT);
            String value = EmbeddedTargetGuard.decodeParam(pair.substring(separator + 1));
            if (value.isBlank()) {
                continue;
            }
            if (WEB_SEED_KEYS.contains(key)) {
                EmbeddedTargetGuard.requireWebSeed(safeUrlValidator, value);
            } else if (TRACKER_KEYS.contains(key)) {
                EmbeddedTargetGuard.requireTracker(safeUrlValidator, value);
            }
        }
    }

    /**
     * magnet: 属于不透明 URI，getRawQuery() 恒为 null，参数只能从方案特定部分里取。
     */
    private static String rawQueryOf(URI magnet) {
        String part = magnet.getRawSchemeSpecificPart();
        if (part == null) {
            return null;
        }
        int mark = part.indexOf('?');
        return mark < 0 ? null : part.substring(mark + 1);
    }

    private ResolvedSource resolveNested(String rawValue) {
        String nested = rawValue == null ? "" : rawValue.trim();
        if (nested.startsWith("//")) {
            nested = nested.substring(2);
        }
        return resolve(nested);
    }

    private boolean looksLikeTorrent(URI uri) {
        String path = uri.getPath();
        return path != null && path.toLowerCase(Locale.ROOT).endsWith(".torrent");
    }
}
