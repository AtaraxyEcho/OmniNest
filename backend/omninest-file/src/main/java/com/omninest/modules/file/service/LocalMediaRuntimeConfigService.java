package com.omninest.modules.file.service;

import com.omninest.common.config.BaseRuntimeConfigService;
import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.config.RuntimeConfigCache;
import com.omninest.modules.file.config.LocalMediaStorageProperties;
import org.springframework.stereotype.Service;

/**
 * 本地媒体运行时配置服务。
 *
 * <p>本地媒体是否启用、扫描文件数与目录深度上限都属于部署边界：只由部署配置决定。
 * 历史配置键留在配置中心隐藏集合中仅用于拒绝旧客户端写入，读取路径刻意忽略它们。
 *
 * @author OmniNest
 */
@Service
public class LocalMediaRuntimeConfigService extends BaseRuntimeConfigService {
    /**
     * 历史配置键。留在隐藏集合中用于拒绝旧客户端写入；读取路径刻意不消费它们的值。
     */
    public static final String ENABLED = "file.local-media.enabled";
    public static final String MAX_FILES_PER_SCAN = "file.local-media.max-files-per-scan";
    public static final String MAX_SCAN_DEPTH = "file.local-media.max-scan-depth";

    private final LocalMediaStorageProperties deploymentProperties;

    /**
     * 创建本地媒体运行时配置服务。
     *
     * @param configValueProvider 配置值查询端口
     * @param runtimeConfigCache 运行时配置缓存端口
     * @param deploymentProperties 部署层本地媒体配置
     */
    public LocalMediaRuntimeConfigService(
            ConfigValueProvider configValueProvider,
            RuntimeConfigCache runtimeConfigCache,
            LocalMediaStorageProperties deploymentProperties
    ) {
        super(configValueProvider, runtimeConfigCache);
        this.deploymentProperties = deploymentProperties;
    }

    /**
     * 判断本地媒体能力是否同时通过部署门禁和运行时开关。
     *
     * @return 是否允许访问本地媒体
     */
    public boolean isEnabled() {
        // 本地路径访问属于部署安全边界，不由配置中心扩大或关闭。
        return deploymentProperties.isEnabled();
    }

    /**
     * 读取单次扫描文件上限。
     *
     * @return 单次扫描文件上限
     */
    public int maxFilesPerScan() {
        return Math.clamp(deploymentProperties.getMaxFilesPerScan(), 1, 1_000_000);
    }

    /**
     * 读取扫描目录深度上限。
     *
     * @return 扫描目录深度上限
     */
    public int maxScanDepth() {
        return Math.clamp(deploymentProperties.getMaxScanDepth(), 1, 128);
    }
}
