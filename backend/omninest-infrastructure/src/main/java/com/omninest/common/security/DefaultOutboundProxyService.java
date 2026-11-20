package com.omninest.common.security;

import com.omninest.common.config.BaseRuntimeConfigService;
import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.config.RuntimeConfigCache;
import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.Proxy;
import java.net.ProxySelector;
import java.net.SocketAddress;
import java.net.URI;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.Set;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * 出站代理的默认实现：代理开关、地址校验与域名白名单都读运行时配置。
 *
 * <p>白名单固定为 TMDB 的 API 与图床域（含管理台自定义的镜像主机），其余目标一律直连。
 * 这样同一个 HttpClient 可以安全地承载其它流量，不会把外部存储或 OAuth 请求送进代理。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Component
public class DefaultOutboundProxyService extends BaseRuntimeConfigService implements OutboundProxyPort {

    public static final String TMDB_PROXY_URL_KEY = "media.tmdb.proxy-url";
    public static final String TMDB_BASE_URL_KEY = "media.tmdb.url";
    public static final String TMDB_IMAGE_URL_KEY = "media.tmdb.image-url";

    private static final String DEFAULT_TMDB_API_HOST = "api.themoviedb.org";
    private static final String DEFAULT_TMDB_IMAGE_HOST = "image.tmdb.org";

    private final ProxySelector dynamicSelector = new ProxySelector() {
        @Override
        public List<Proxy> select(URI uri) {
            if (uri == null || !shouldProxy(uri)) {
                return List.of(Proxy.NO_PROXY);
            }
            try {
                return resolveConfiguredProxyUri()
                        .map(proxyUri -> List.of(new Proxy(
                                Proxy.Type.HTTP,
                                InetSocketAddress.createUnresolved(proxyUri.getHost(), proxyUri.getPort()))))
                        .orElseGet(() -> List.of(Proxy.NO_PROXY));
            } catch (BusinessException ex) {
                // 前置校验已拦截非法配置；此处只防配置在校验与建连之间被改坏，
                // ProxySelector.select 抛异常会落进 JDK 内部未预期路径。
                log.warn("出站代理选择时配置无效: targetHost={}, message={}", uri.getHost(), ex.getMessage());
                return List.of(Proxy.NO_PROXY);
            }
        }

        @Override
        public void connectFailed(URI uri, SocketAddress sa, IOException ioe) {
            log.warn("出站代理建连失败: targetHost={}, proxy={}, errorType={}",
                    uri == null ? "unknown" : uri.getHost(),
                    sa,
                    ioe == null ? "unknown" : ioe.getClass().getSimpleName());
        }
    };

    public DefaultOutboundProxyService(ConfigValueProvider configValueProvider, RuntimeConfigCache runtimeConfigCache) {
        super(configValueProvider, runtimeConfigCache);
    }

    @Override
    public boolean shouldProxy(URI target) {
        if (target == null || target.getHost() == null) {
            return false;
        }
        String rawProxy = cachedConfigValue(TMDB_PROXY_URL_KEY).map(String::trim).orElse("");
        if (rawProxy.isEmpty()) {
            return false;
        }
        return allowedProxyHosts().contains(normalizeHost(target.getHost()));
    }

    @Override
    public Optional<URI> resolveConfiguredProxyUri() {
        String raw = cachedConfigValue(TMDB_PROXY_URL_KEY).map(String::trim).orElse("");
        if (raw.isEmpty()) {
            return Optional.empty();
        }
        URI uri;
        try {
            uri = URI.create(raw);
        } catch (IllegalArgumentException ex) {
            throw new BusinessException(ErrorCode.CONFIG_VALUE_INVALID, "出站代理地址格式无效");
        }
        if (!"http".equalsIgnoreCase(uri.getScheme())
                || uri.getHost() == null
                || uri.getHost().isBlank()
                || uri.getPort() <= 0
                || uri.getPort() > 65535
                || uri.getUserInfo() != null) {
            throw new BusinessException(ErrorCode.CONFIG_VALUE_INVALID,
                    "代理地址仅支持无凭据的 http://host:port 格式");
        }
        return Optional.of(uri);
    }

    @Override
    public ProxySelector proxySelector() {
        return dynamicSelector;
    }

    private Set<String> allowedProxyHosts() {
        Set<String> hosts = new LinkedHashSet<>();
        hosts.add(DEFAULT_TMDB_API_HOST);
        hosts.add(DEFAULT_TMDB_IMAGE_HOST);
        extractHost(TMDB_BASE_URL_KEY).ifPresent(hosts::add);
        extractHost(TMDB_IMAGE_URL_KEY).ifPresent(hosts::add);
        return hosts;
    }

    private Optional<String> extractHost(String key) {
        return cachedConfigValue(key)
                .map(String::trim)
                .filter(value -> !value.isEmpty())
                .flatMap(value -> {
                    try {
                        URI uri = URI.create(value);
                        String host = uri.getHost();
                        return host == null || host.isBlank()
                                ? Optional.empty()
                                : Optional.of(normalizeHost(host));
                    } catch (IllegalArgumentException ex) {
                        return Optional.empty();
                    }
                });
    }

    private String normalizeHost(String host) {
        String normalized = host.toLowerCase(Locale.ROOT);
        while (normalized.endsWith(".")) {
            normalized = normalized.substring(0, normalized.length() - 1);
        }
        return normalized;
    }
}
