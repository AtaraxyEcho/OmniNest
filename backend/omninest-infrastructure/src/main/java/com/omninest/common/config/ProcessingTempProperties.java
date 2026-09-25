package com.omninest.common.config;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import lombok.Getter;
import lombok.Setter;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * 媒体转码、缩略图等派生处理的本地临时目录根配置。
 *
 * <p>业务模块不得直接拼接系统临时目录；统一从本配置解析子目录，
 * 避免挤占 PostgreSQL/MinIO 数据目录或系统盘根路径。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Getter
@Setter
@Component
@ConfigurationProperties(prefix = "omninest.processing")
public class ProcessingTempProperties {

    /**
     * 处理目录根路径；默认落在系统临时目录下的独立子目录。
     */
    private String root = Path.of(System.getProperty("java.io.tmpdir"), "omninest-processing").toString();

    /**
     * 解析并确保存在指定业务子目录。
     *
     * @param segment 业务子目录名，例如 music-cover 或 transcode
     * @return 可用的处理子目录
     */
    public Path ensureSubdirectory(String segment) {
        Path base = Path.of(root).toAbsolutePath().normalize();
        Path resolved = (segment == null || segment.isBlank() || ".".equals(segment))
                ? base
                : base.resolve(segment).normalize();
        if (!resolved.startsWith(base)) {
            throw new IllegalArgumentException("处理子目录越界: " + segment);
        }
        try {
            Files.createDirectories(resolved);
        } catch (IOException exception) {
            throw new UncheckedIOException("创建处理目录失败: " + resolved, exception);
        }
        return resolved;
    }

    /**
     * 返回处理根目录（确保存在）。
     *
     * @return 处理根目录
     */
    public Path ensureRoot() {
        return ensureSubdirectory(null);
    }
}
