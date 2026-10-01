package com.omninest.modules.file.config;

import java.util.ArrayList;
import java.util.List;
import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 外部存储端点安全策略。
 *
 * <p>外部存储的 WEBDAV url 与 S3 endpoint 由用户提交并最终由 rclone 容器发起请求，
 * 默认仅允许公网 HTTP(S) 地址与 80/443 端口；确需连接局域网 NAS 的部署由管理员显式放开内网地址。
 *
 * @author OmniNest
 */
@Data
@ConfigurationProperties(prefix = "omninest.external-storage.endpoint")
public class ExternalStorageEndpointPolicyProperties {

    /**
     * 是否允许连接内网专用地址（RFC1918 与 IPv6 唯一本地地址）。
     * 环回、链路本地与云元数据地址在任何配置下都拒绝。
     */
    private boolean allowPrivateNetwork = false;

    /**
     * 允许的显式端口号；未书写端口的 URL 按协议默认端口处理。
     */
    private List<Integer> allowedPorts = new ArrayList<>(List.of(80, 443));
}
