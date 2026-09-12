package com.omninest.modules.system.service;

import com.omninest.common.config.BaseRuntimeConfigService;
import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.config.RuntimeConfigCache;
import org.springframework.stereotype.Service;

/**
 * 应用版本检查策略，从配置中心读取最新客户端版本信息。
 *
 * <p>自托管"检查更新"场景：管理员在配置中心维护 latest 版本号、发布说明与下载地址；
 * 未配置（空）时客户端视为已是最新版本。</p>
 *
 * @author OmniNest
 */
@Service
public class AppVersionPolicyService extends BaseRuntimeConfigService {

    /** 最新客户端版本号（如 1.4.0）。 */
    public static final String LATEST_VERSION_KEY = "app.version.latest";
    /** 当前版本的发布说明 URL（相对页面或外链）。 */
    public static final String RELEASE_NOTES_URL_KEY = "app.version.release-notes-url";
    /** 安装包下载页 URL。 */
    public static final String DOWNLOAD_URL_KEY = "app.version.download-url";

    /**
     * 创建应用版本策略服务。
     *
     * @param configValueProvider 配置值查询端口
     * @param runtimeConfigCache 运行时配置缓存端口
     */
    public AppVersionPolicyService(
            ConfigValueProvider configValueProvider,
            RuntimeConfigCache runtimeConfigCache
    ) {
        super(configValueProvider, runtimeConfigCache);
    }

    /**
     * 读取指定键的字符串值，空值归一为 null。
     */
    public String stringValue(String key) {
        return cachedConfigValue(key)
                .map(value -> value == null ? "" : value.trim())
                .filter(value -> !value.isEmpty())
                .orElse(null);
    }
}
