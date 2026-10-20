package com.omninest.modules.notification.config;

import com.omninest.common.config.BaseRuntimeConfigService;
import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.config.RuntimeConfigCache;
import org.springframework.stereotype.Service;

/**
 * 通知邮件通道运行配置，全部取自配置中心受控目录，默认关闭。
 *
 * <p>口令是敏感项，读取时由配置值查询端口自动解密，因此本类任何方法都不得
 * 把返回值写进日志或错误摘要。</p>
 *
 * @author OmniNest
 */
@Service
public class NotificationEmailRuntimeConfig extends BaseRuntimeConfigService {

    private static final String ENABLED_KEY = "notification.email.enabled";
    private static final String HOST_KEY = "notification.email.host";
    private static final String PORT_KEY = "notification.email.port";
    private static final String USERNAME_KEY = "notification.email.username";
    private static final String PASSWORD_KEY = "notification.email.password";
    private static final String FROM_KEY = "notification.email.from";
    private static final String STARTTLS_KEY = "notification.email.starttls";
    private static final String TIMEOUT_KEY = "notification.email.timeout-millis";

    /**
     * 创建邮件通道配置服务。
     *
     * @param configValueProvider 配置值查询端口
     * @param runtimeConfigCache 运行时配置缓存端口
     */
    public NotificationEmailRuntimeConfig(
            ConfigValueProvider configValueProvider,
            RuntimeConfigCache runtimeConfigCache
    ) {
        super(configValueProvider, runtimeConfigCache);
    }

    /**
     * 通道开关：关闭时不产生任何投递任务。
     *
     * @return 已启用时返回 true
     */
    public boolean enabled() {
        return booleanConfig(ENABLED_KEY, false);
    }

    /**
     * 判断通道是否具备可用的 SMTP 参数。
     *
     * @return 开关开启且主机非空时返回 true
     */
    public boolean configured() {
        return enabled() && !host().isBlank();
    }

    /**
     * SMTP 服务器主机。
     *
     * @return 主机名，未配置时为空串
     */
    public String host() {
        return stringConfig(HOST_KEY, "");
    }

    /**
     * SMTP 服务器端口。
     *
     * @return 端口号，缺省 587
     */
    public int port() {
        return intConfig(PORT_KEY, 587);
    }

    /**
     * SMTP 登录账号，未配置表示匿名投递。
     *
     * @return 账号，未配置时为空串
     */
    public String username() {
        return stringConfig(USERNAME_KEY, "");
    }

    /**
     * SMTP 登录口令明文（已由配置端口解密），仅供建立连接使用。
     *
     * @return 口令，未配置时为空串
     */
    public String password() {
        return stringConfig(PASSWORD_KEY, "");
    }

    /**
     * 发件人地址，留空时回落登录账号。
     *
     * @return 发件人地址
     */
    public String from() {
        String configuredFrom = stringConfig(FROM_KEY, "");
        return configuredFrom.isBlank() ? username() : configuredFrom;
    }

    /**
     * 是否使用 STARTTLS。
     *
     * @return 需要加密连接时返回 true，默认 true
     */
    public boolean starttls() {
        return booleanConfig(STARTTLS_KEY, true);
    }

    /**
     * SMTP 连接与读取时限。
     *
     * @return 毫秒数，缺省 10000
     */
    public int timeoutMillis() {
        return intConfig(TIMEOUT_KEY, 10_000);
    }
}
