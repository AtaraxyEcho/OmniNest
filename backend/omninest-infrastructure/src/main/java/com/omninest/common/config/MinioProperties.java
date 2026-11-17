package com.omninest.common.config;

import com.omninest.common.storage.ObjectStorageBuckets;
import lombok.Data;
import lombok.ToString;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * MinIO 对象存储配置属性。
 *
 * @author OmniNest
 */
@Data
@ConfigurationProperties(prefix = "omninest.minio")
public class MinioProperties implements ObjectStorageBuckets {
    private String endpoint;

    /**
     * 客户端访问预签名地址时使用的公开端点。
     */
    private String publicEndpoint;

    /**
     * Docker 内部网络访问 MinIO 的端点（如 http://omninest-minio:9000）。
     * 为空时回退到 endpoint。
     */
    private String dockerEndpoint;

    @ToString.Exclude
    private String accessKey;

    @ToString.Exclude
    private String secretKey;

    private int apiCallTimeoutSeconds = 1800;

    /**
     * 单次 HTTP 请求尝试超时（秒）。
     * 大文件删除/读取需要较长的单次尝试超时。
     */
    private int apiCallAttemptTimeoutSeconds = 900;

    private Buckets buckets = new Buckets();

    /**
     * 获取用户文件存储桶名称。
     *
     * @return 用户文件存储桶名称
     */
    @Override
    public String userFiles() {
        return buckets.getUserFiles();
    }

    /**
     * 获取衍生资源存储桶名称。
     *
     * @return 衍生资源存储桶名称
     */
    @Override
    public String derivedAssets() {
        return buckets.getDerivedAssets();
    }

    /**
     * 获取文件安全扫描隔离桶名称。
     *
     * @return 隔离桶名称
     */
    @Override
    public String quarantine() {
        return buckets.getQuarantine();
    }

    /**
     * MinIO 存储桶名称配置。
     *
     * @author OmniNest
     */
    @Data
    public static class Buckets {
        private String userFiles = "user-files";

        private String derivedAssets = "derived-assets";

        private String quarantine = "file-quarantine";

    }
}
