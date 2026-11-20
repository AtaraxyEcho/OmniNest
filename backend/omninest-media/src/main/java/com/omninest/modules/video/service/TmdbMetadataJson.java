package com.omninest.modules.video.service;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import tools.jackson.databind.JsonNode;

/**
 * TMDB 详情里的数组字段解析。从提供器拆出，避免单文件突破 800 行软上限。
 *
 * @author OmniNest
 */
final class TmdbMetadataJson {

    private TmdbMetadataJson() {
    }

    static List<String> extractGenreNames(JsonNode genres) {
        if (genres == null || !genres.isArray() || genres.isEmpty()) {
            return List.of();
        }
        List<String> names = new ArrayList<>();
        for (int i = 0; i < genres.size(); i++) {
            String name = genres.get(i).path("name").asString(null);
            if (name != null && !name.isBlank()) {
                names.add(name);
            }
        }
        return names;
    }

    static List<Map<String, Object>> parseCompanyList(JsonNode companies) {
        if (companies == null || !companies.isArray() || companies.isEmpty()) {
            return List.of();
        }
        List<Map<String, Object>> result = new ArrayList<>();
        for (int i = 0; i < companies.size(); i++) {
            JsonNode company = companies.get(i);
            Map<String, Object> map = new LinkedHashMap<>();
            map.put("id", company.hasNonNull("id") ? company.path("id").asInt() : null);
            map.put("name", text(company, "name"));
            map.put("origin_country", text(company, "origin_country"));
            result.add(map);
        }
        return result;
    }

    static List<Map<String, Object>> parseCountryList(JsonNode countries) {
        if (countries == null || !countries.isArray() || countries.isEmpty()) {
            return List.of();
        }
        List<Map<String, Object>> result = new ArrayList<>();
        for (int i = 0; i < countries.size(); i++) {
            JsonNode country = countries.get(i);
            Map<String, Object> map = new LinkedHashMap<>();
            map.put("iso_3166_1", text(country, "iso_3166_1"));
            map.put("name", text(country, "name"));
            result.add(map);
        }
        return result;
    }

    private static String text(JsonNode item, String key) {
        String value = item.path(key).asString(null);
        return value == null ? "" : value.trim();
    }
}
