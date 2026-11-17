package com.omninest.modules.photos.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * GeoNames 离线数据导入目录配置。
 *
 * <p>四个 dump 文件（cities5000.txt、admin1CodesASCII.txt、countryInfo.txt、
 * alternateNamesV2.txt）由管理员直接放置在该共享目录下，不通过 multipart 上传；
 * 多实例部署时至少 Worker 实例必须挂载该目录。dump 日期仅用于数据集版本记录。</p>
 *
 * @author OmniNest
 */
@Data
@Component
@ConfigurationProperties(prefix = "photo.geo.import")
public class GeonamesImportProperties {

    /** GeoNames 数据文件根目录（共享目录） */
    private String dir = "./data/geonames";
}
