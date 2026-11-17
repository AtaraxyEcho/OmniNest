package com.omninest.modules.photos.service;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 位置名称双语格式化器。
 *
 * <p>地理数据层与 locale 解耦：一次命中同时产出中英文展示字段，
 * 语言切换只需在已持久化的字段间选择，不触发任何地理计算。</p>
 *
 * @author OmniNest
 */
public final class GeoLocationFormatter {

    private static final String SEPARATOR = " · ";
    private static final String GEOCODER_GEONAMES = "geonames";

    private GeoLocationFormatter() {
    }

    /**
     * 将最近城市命中结果格式化为 gps_location 持久化结构。
     *
     * <p>同时保留中英文（city/state/country/displayName 与 *Zh），
     * 并附带 geonameId、distanceKm 与 geocoder 标识。</p>
     *
     * @param match 最近城市命中结果
     * @return gps_location 键值对
     */
    public static Map<String, Object> toGpsLocation(GeoCityMatch match) {
        GeoCitySnapshot.Entry city = match.city();
        Map<String, Object> result = new LinkedHashMap<>();
        putIfNotBlank(result, "city", city.name());
        putIfNotBlank(result, "cityZh", city.nameZh());
        putIfNotBlank(result, "state", city.provinceNameEn());
        putIfNotBlank(result, "stateZh", city.provinceNameZh());
        putIfNotBlank(result, "country", city.countryNameEn());
        putIfNotBlank(result, "countryZh", city.countryNameZh());
        putIfNotBlank(result, "displayName", displayName(
                Arrays.asList(city.countryNameEn(), city.provinceNameEn(), city.name())));
        putIfNotBlank(result, "displayNameZh", displayName(
                Arrays.asList(city.countryNameZh(), city.provinceNameZh(), city.nameZh())));
        result.put("geonameId", city.geonameId());
        result.put("distanceKm", roundKm(match.distanceKm()));
        result.put("geocoder", GEOCODER_GEONAMES);
        return Map.copyOf(result);
    }

    /**
     * 国家 · 省 · 城市拼接，跳过空值。
     *
     * @param parts 候选片段
     * @return 拼接结果，全空时返回 null
     */
    public static String displayName(List<String> parts) {
        List<String> present = new ArrayList<>();
        for (String part : parts) {
            if (part != null && !part.isBlank()) {
                present.add(part.trim());
            }
        }
        if (present.isEmpty()) {
            return null;
        }
        return String.join(SEPARATOR, present);
    }

    private static double roundKm(double distanceKm) {
        return Math.round(distanceKm * 100.0) / 100.0;
    }

    private static void putIfNotBlank(Map<String, Object> target, String key, String value) {
        if (value != null && !value.isBlank()) {
            target.put(key, value);
        }
    }
}
