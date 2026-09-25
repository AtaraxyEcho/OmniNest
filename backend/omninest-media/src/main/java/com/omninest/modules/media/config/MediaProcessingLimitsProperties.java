package com.omninest.modules.media.config;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * 媒体派生处理的文件大小阈值配置。
 *
 * <p>业务服务只读本配置，不再散落魔法数；默认值与历史硬编码一致，避免隐性收紧。</p>
 *
 * @author OmniNest
 */
@Getter
@Setter
@Component
@ConfigurationProperties(prefix = "media.processing-limits")
public class MediaProcessingLimitsProperties {

    /** 音乐封面上传上限 */
    private long maxCoverUploadBytes = 8L * 1024 * 1024;

    /** 音乐流封面读取上限 */
    private long maxStreamCoverBytes = 32L * 1024 * 1024;

    /** 内嵌封面字节上限 */
    private long maxEmbeddedCoverBytes = 8L * 1024 * 1024;

    /** 封面缩略图原图上限 */
    private long maxCoverThumbnailSourceBytes = 8L * 1024 * 1024;

    /** 字幕内容上限 */
    private long maxSubtitleBytes = 10L * 1024 * 1024;

    /** 漫画页图上限 */
    private long maxComicPageImageBytes = 20L * 1024 * 1024;

    /** 阅读封面上限 */
    private long maxReaderCoverBytes = 20L * 1024 * 1024;
}
