package com.omninest.modules.backdrop.config;

import com.omninest.common.config.BaseRuntimeConfigService;
import com.omninest.common.config.ConfigValueProvider;
import com.omninest.common.config.RuntimeConfigCache;
import org.springframework.stereotype.Service;

/**
 * 背景库模块运行时配置服务。
 * 从配置中心读取素材大小、数量与上传频率限制，默认值与 V002 种子保持一致。
 *
 * @author OmniNest
 */
@Service
public class BackdropRuntimeConfigService extends BaseRuntimeConfigService {

    public static final String MAX_IMAGE_BYTES = "backdrop.max-image-bytes";
    public static final String MAX_VIDEO_BYTES = "backdrop.max-video-bytes";
    public static final String MAX_ASSETS_PER_USER = "backdrop.max-assets-per-user";
    public static final String UPLOAD_RATE_PER_HOUR = "backdrop.upload.rate-per-hour";

    private static final long DEFAULT_MAX_IMAGE_BYTES = 20L * 1024 * 1024;
    private static final long DEFAULT_MAX_VIDEO_BYTES = 448L * 1024 * 1024;
    private static final int DEFAULT_MAX_ASSETS_PER_USER = 30;
    private static final int DEFAULT_UPLOAD_RATE_PER_HOUR = 20;

    /**
     * 创建背景库运行时配置服务。
     *
     * @param configValueProvider 配置值查询端口
     * @param runtimeConfigCache 运行时配置缓存端口
     */
    public BackdropRuntimeConfigService(
            ConfigValueProvider configValueProvider,
            RuntimeConfigCache runtimeConfigCache
    ) {
        super(configValueProvider, runtimeConfigCache);
    }

    /**
     * 背景图片单文件大小上限。
     * 可调区间只由配置中心目录的取值范围声明,此处不再重复钳制。
     *
     * @return 大小上限（字节）
     */
    public long maxImageBytes() {
        return longConfig(MAX_IMAGE_BYTES, DEFAULT_MAX_IMAGE_BYTES);
    }

    /**
     * 背景视频单文件大小上限。
     * 可调区间只由配置中心目录的取值范围声明,其上界对齐 Spring multipart 的传输上限,
     * 因此无需在应用内重复设置硬编码边界。
     *
     * @return 大小上限（字节）
     */
    public long maxVideoBytes() {
        return longConfig(MAX_VIDEO_BYTES, DEFAULT_MAX_VIDEO_BYTES);
    }

    /**
     * 每用户背景素材数量上限。
     *
     * @return 数量上限
     */
    public int maxAssetsPerUser() {
        return Math.clamp(intConfig(MAX_ASSETS_PER_USER, DEFAULT_MAX_ASSETS_PER_USER), 1, 200);
    }

    /**
     * 每用户每小时上传次数上限。
     *
     * @return 次数上限
     */
    public int uploadRatePerHour() {
        return Math.clamp(intConfig(UPLOAD_RATE_PER_HOUR, DEFAULT_UPLOAD_RATE_PER_HOUR), 1, 1000);
    }
}
