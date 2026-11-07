package com.omninest.common.config;

import java.util.List;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.stereotype.Component;

/**
 * 启动时提示可信代理未配置。
 *
 * <p>客户端 IP 只在直连对端命中可信代理清单时才采信转发头。清单留空本身是合法配置
 * （直接暴露端口、无反代），但部署在反向代理之后却忘记配置时，所有请求都会退化成
 * 代理地址：IP 维度的登录/注册限流被全站共享，登录审计也只剩一个 IP。这类事故不报错、
 * 只表现为"偶发被限流"，因此必须在启动时留下一条可检索的告警。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class TrustedProxyWarning implements ApplicationRunner {

    private final SecurityProperties securityProperties;

    @Override
    public void run(ApplicationArguments args) {
        warnIfUnset();
    }

    void warnIfUnset() {
        List<String> trustedProxies = securityProperties.getTrustedProxies();
        boolean configured = trustedProxies != null
                && trustedProxies.stream().anyMatch(value -> value != null && !value.isBlank());
        if (configured) {
            return;
        }
        log.warn("未配置可信代理（omninest.security.trusted-proxies）："
                + "若服务部署在反向代理之后，客户端 IP 将退化为代理地址，"
                + "按 IP 的限流与登录审计会按代理聚合；"
                + "请通过 OMNINEST_SECURITY_TRUSTED_PROXIES 填入代理出口网段");
    }
}
