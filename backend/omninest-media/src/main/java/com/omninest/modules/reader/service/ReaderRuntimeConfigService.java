package com.omninest.modules.reader.service;

import com.omninest.common.config.BaseRuntimeConfigService;
import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.config.RuntimeConfigCache;
import org.springframework.stereotype.Service;

/**
 * 阅读模块运行时配置服务。
 *
 * <p>自动导入开关由配置中心控制，旧键只用于迁移观察期兼容读取。
 */
@Service
public class ReaderRuntimeConfigService extends BaseRuntimeConfigService {

    public static final String AUTO_IMPORT_ENABLED = "reader.import.enabled";

    public ReaderRuntimeConfigService(
            ConfigValueProvider configValueProvider,
            RuntimeConfigCache runtimeConfigCache
    ) {
        super(configValueProvider, runtimeConfigCache);
    }

    public boolean autoImportEnabled() {
        return cachedConfigValue(AUTO_IMPORT_ENABLED)
                .or(() -> cachedConfigValue("reader.auto-import.enabled"))
                .map(value -> parseBoolean(value, true))
                .orElse(true);
    }
}
