package com.omninest.modules.notification.config;

import com.omninest.common.config.BaseRuntimeConfigService;
import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.config.RuntimeConfigCache;
import java.util.Locale;
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
    private static final String SECURITY_KEY = "notification.email.security";
    private static final String TRUST_HOSTS_KEY = "notification.email.trust-hosts";
    private static final String TIMEOUT_KEY = "notification.email.timeout-millis";
    private static final String FORMAT_KEY = "notification.email.format";
    private static final String WEB_BASE_URL_KEY = "notification.email.web-base-url";
    private static final String RATE_PER_HOUR_KEY = "notification.email.rate-per-hour";

    /** SMTP 加密方式：明文、STARTTLS 升级、隐式 TLS（465 一类端口）。 */
    public enum TransportSecurity {
        NONE,
        STARTTLS,
        SSL
    }

    /** 正文格式：纯文本，或纯文本加等价 HTML 的多部件邮件。 */
    public enum MessageFormat {
        PLAIN,
        RICH
    }

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
     * SMTP 加密方式；目录外的取值按缺省 STARTTLS 处理，不用明文兜底。
     *
     * @return 加密方式
     */
    public TransportSecurity security() {
        return parseEnum(SECURITY_KEY, TransportSecurity.STARTTLS, TransportSecurity.class);
    }

    /**
     * 跳过证书校验的主机清单；空串表示严格校验证书链。
     *
     * @return 逗号分隔主机清单
     */
    public String trustHosts() {
        return stringConfig(TRUST_HOSTS_KEY, "");
    }

    /**
     * SMTP 连接与读取时限。
     *
     * @return 毫秒数，缺省 10000
     */
    public int timeoutMillis() {
        return intConfig(TIMEOUT_KEY, 10_000);
    }

    /**
     * 正文格式，默认纯文本；取值异常同样回落纯文本。
     *
     * @return 正文格式
     */
    public MessageFormat format() {
        return parseEnum(FORMAT_KEY, MessageFormat.PLAIN, MessageFormat.class);
    }

    /**
     * 邮件内链接指向的站点地址。
     *
     * @return 站点地址，未配置时为空串
     */
    public String webBaseUrl() {
        return stringConfig(WEB_BASE_URL_KEY, "");
    }

    /**
     * 每用户每小时邮件投递上限。
     *
     * @return 上限，0 表示不限制
     */
    public int ratePerHour() {
        return intConfig(RATE_PER_HOUR_KEY, 30);
    }

    private <T extends Enum<T>> T parseEnum(String key, T fallback, Class<T> type) {
        String raw = stringConfig(key, fallback.name());
        try {
            return Enum.valueOf(type, raw.trim().toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException exception) {
            return fallback;
        }
    }
}
