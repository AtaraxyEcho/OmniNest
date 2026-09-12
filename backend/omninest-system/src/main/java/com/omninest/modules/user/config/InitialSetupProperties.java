package com.omninest.modules.user.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 首次安装向导的服务端安全配置。
 *
 * @author OmniNest
 */
@Data
@ConfigurationProperties(prefix = "omninest.setup")
public class InitialSetupProperties {
    private boolean enabled = true;
    private String token;
    private boolean persistentStateEnabled = true;
    private String webBaseUrl;

    /**
     * 安装向导是否要求完成两步验证注册；对应环境变量 OMNINEST_SETUP_TWOFACTORREQUIRED。
     * 默认 false（不强制），公网部署在 deploy/prod 模板显式设为 true。
     */
    private boolean twoFactorRequired = false;
}
