package com.omninest.modules.configcenter.service;

import lombok.RequiredArgsConstructor;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

/**
 * API 角色启动时通过受事务代理保护的服务同步配置目录。
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
@RequiredArgsConstructor
@ConditionalOnProperty(name = "omninest.runtime.role", havingValue = "api", matchIfMissing = true)
public class ConfigCatalogInitializer implements ApplicationRunner {
    private final ConfigCenterService configCenterService;

    @Override
    public void run(ApplicationArguments args) {
        configCenterService.initializeCatalog();
    }
}
