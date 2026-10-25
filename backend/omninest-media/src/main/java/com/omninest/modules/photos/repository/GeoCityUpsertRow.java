package com.omninest.modules.photos.repository;

import java.math.BigDecimal;

/**
 * 待写入的单条 GeoNames 城市记录。
 *
 * <p>基础导入阶段不携带中文名，中文名由别名阶段单独回填。</p>
 *
 * @param geonameId GeoNames 城市 ID
 * @param name 主名称
 * @param countryCode ISO 国家码
 * @param countryNameEn 国家英文名
 * @param provinceNameEn 一级行政区英文名
 * @param latitude 纬度
 * @param longitude 经度
 * @param population 人口
 * @param featureCode 地物类型代码
 * @author OmniNest
 */
public record GeoCityUpsertRow(
        long geonameId,
        String name,
        String countryCode,
        String countryNameEn,
        String provinceNameEn,
        BigDecimal latitude,
        BigDecimal longitude,
        long population,
        String featureCode
) {
}
