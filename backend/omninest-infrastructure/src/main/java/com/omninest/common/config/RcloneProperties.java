package com.omninest.common.config;

import com.omninest.common.storage.LocalExternalStorageSettings;
import java.time.Duration;
import lombok.Data;
import lombok.ToString;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Rclone RC API 配置属性。
 *
 * @author OmniNest
 */
@Data
@ConfigurationProperties(prefix = "omninest.rclone")
public class RcloneProperties implements LocalExternalStorageSettings {
    private String endpoint = "http://localhost:5572";
    private String username = "";
    @ToString.Exclude
    private String password = "";
    private int connectTimeoutSeconds = 10;
    private int readTimeoutSeconds = 300;
    private Duration metadataCacheTtl = Duration.ofMinutes(60);

    /**
     * rclone 容器内 /mnt/local 对应的宿主机路径。
     * <p>
     * LOCAL 类型外部存储导入时，后端直接从此路径读取文件上传到 MinIO，
     * 绕过 rclone（避免容器内无法访问宿主机临时目录的问题）。
     * <p>
     * 默认值指向项目根目录的 .omninest/local-files（后端工作目录为 backend/，需 ../ 回退一级）。
     */
    private String localHostPath = "../.omninest/local-files";
    private String importHostPath = "../.omninest/rclone-imports";
    private String importContainerPath = "/mnt/imports";

    /**
     * 获取本地外部存储的宿主机根路径。
     *
     * @return 宿主机根路径
     */
    @Override
    public String localHostRoot() {
        return localHostPath;
    }

    /**
     * 获取导入暂存目录的宿主机路径。
     *
     * @return 宿主机暂存路径
     */
    @Override
    public String importHostRoot() {
        return importHostPath;
    }

    /**
     * 获取导入暂存目录的 rclone 容器路径。
     *
     * @return 容器暂存路径
     */
    @Override
    public String importContainerRoot() {
        return importContainerPath;
    }
}
