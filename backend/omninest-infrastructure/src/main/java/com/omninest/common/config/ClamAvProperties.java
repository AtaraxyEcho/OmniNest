package com.omninest.common.config;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * ClamAV 文件扫描连接配置。
 *
 * @author OmniNest
 */
@ConfigurationProperties(prefix = "omninest.clamav")
public class ClamAvProperties {
    private boolean enabled = true;
    private String host = "localhost";
    private int port = 3310;
    private Duration timeout = Duration.ofSeconds(10);

    /**
     * 获取是否启用文件安全扫描。
     *
     * @return 是否启用扫描
     */
    public boolean isEnabled() {
        return enabled;
    }

    /**
     * 设置是否启用文件安全扫描。
     *
     * @param enabled 是否启用扫描
     */
    public void setEnabled(boolean enabled) {
        this.enabled = enabled;
    }

    /**
     * 获取 clamd 主机地址。
     *
     * @return clamd 主机地址
     */
    public String getHost() {
        return host;
    }

    /**
     * 设置 clamd 主机地址。
     *
     * @param host clamd 主机地址
     */
    public void setHost(String host) {
        this.host = host;
    }

    /**
     * 获取 clamd TCP 端口。
     *
     * @return clamd TCP 端口
     */
    public int getPort() {
        return port;
    }

    /**
     * 设置 clamd TCP 端口。
     *
     * @param port clamd TCP 端口
     */
    public void setPort(int port) {
        this.port = port;
    }

    /**
     * 获取单文件扫描时限。
     *
     * @return 单文件扫描时限
     */
    public Duration getTimeout() {
        return timeout;
    }

    /**
     * 设置单文件扫描时限。
     *
     * @param timeout 单文件扫描时限
     */
    public void setTimeout(Duration timeout) {
        this.timeout = timeout;
    }
}
