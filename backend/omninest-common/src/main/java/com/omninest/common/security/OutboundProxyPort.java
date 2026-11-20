package com.omninest.common.security;

import java.net.ProxySelector;
import java.net.URI;
import java.util.Optional;

/**
 * 出站代理路由端口：按配置的域名白名单决定是否经代理出网。
 *
 * <p>抽象成端口是为了让 {@code omninest-file}、{@code omninest-media} 不必依赖
 * {@code omninest-infrastructure} 的实现类，方向符合模块边界。</p>
 *
 * @author OmniNest
 */
public interface OutboundProxyPort {

    /**
     * 目标是否属于代理白名单且当前配置了代理。
     *
     * @param target 目标地址
     * @return 应经代理时返回 {@code true}
     */
    boolean shouldProxy(URI target);

    /**
     * 读取校验通过的代理地址；未配置返回空。
     *
     * @return 代理地址
     * @throws com.omninest.common.error.BusinessException 配置存在但格式非法
     */
    Optional<URI> resolveConfiguredProxyUri();

    /**
     * 供长生命周期 HttpClient 复用的动态选择器，配置变更无需重建客户端。
     *
     * @return 代理选择器
     */
    ProxySelector proxySelector();
}
