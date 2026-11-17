package com.omninest.modules.photos.service;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * GeoNames dump 文件解析器。
 *
 * <p>统一处理 cities5000、admin1CodesASCII、countryInfo 与 alternateNamesV2 四类文件，
 * 逐行流式解析，大文件不整体载入内存。</p>
 *
 * @author OmniNest
 */
@Slf4j
@Component
public class GeoNamesParser {

    /** cities5000 单行解析结果。 */
    public record CityRow(
            long geonameId,
            String name,
            BigDecimal latitude,
            BigDecimal longitude,
            String featureCode,
            String countryCode,
            String admin1Code,
            long population) {
    }

    /** admin1CodesASCII 单行解析结果，key 为 countryCode.admin1Code。 */
    public record Admin1Entry(long geonameId, String nameEn) {
    }

    /** countryInfo 单行解析结果，key 为 ISO 国家码。 */
    public record CountryEntry(long geonameId, String nameEn) {
    }

    /** alternateNamesV2 单行候选。 */
    public record AlternateName(long geonameId, String language, String name, boolean preferred, boolean historic) {
    }

    /** 城市行消费回调。 */
    @FunctionalInterface
    public interface CityRowHandler {

        /**
         * 处理单行城市数据。
         *
         * @param row 城市行
         * @throws IOException 读取或写入失败
         */
        void handle(CityRow row) throws IOException;
    }

    /** 别名候选消费回调。 */
    @FunctionalInterface
    public interface AlternateNameHandler {

        /**
         * 处理单条别名候选。
         *
         * @param name 别名候选
         * @throws IOException 读取或写入失败
         */
        void handle(AlternateName name) throws IOException;
    }

    /**
     * 流式解析 cities5000.txt。
     *
     * @param input 文件输入流
     * @param handler 单行回调
     * @throws IOException 读取失败
     */
    public void streamCities(InputStream input, CityRowHandler handler) throws IOException {
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(input, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.isBlank() || line.startsWith("#")) {
                    continue;
                }
                String[] cols = line.split("\\t");
                if (cols.length < 15) {
                    continue;
                }
                try {
                    handler.handle(new CityRow(
                            Long.parseLong(cols[0]),
                            cols[1],
                            new BigDecimal(cols[4]),
                            new BigDecimal(cols[5]),
                            blankToNull(cols[7]),
                            blankToNull(cols[8]),
                            blankToNull(cols[10]),
                            parseLong(cols[14])));
                } catch (NumberFormatException ignored) {
                    logSkip("cities5000", cols[0]);
                }
            }
        }
    }

    /**
     * 解析 admin1CodesASCII.txt。geonameid 位于最后一列（第 4 列），名称取 ASCII 列。
     *
     * @param input 文件输入流
     * @return key = countryCode.admin1Code
     * @throws IOException 读取失败
     */
    public Map<String, Admin1Entry> parseAdmin1Codes(InputStream input) throws IOException {
        Map<String, Admin1Entry> result = new HashMap<>();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(input, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.isBlank() || line.startsWith("#")) {
                    continue;
                }
                String[] cols = line.split("\\t");
                if (cols.length < 4) {
                    continue;
                }
                try {
                    result.put(cols[0], new Admin1Entry(Long.parseLong(cols[3]), firstNotBlank(cols[2], cols[1])));
                } catch (NumberFormatException ignored) {
                    logSkip("admin1CodesASCII", cols[0]);
                }
            }
        }
        return result;
    }

    /**
     * 解析 countryInfo.txt。
     *
     * @param input 文件输入流
     * @return key = ISO 国家码
     * @throws IOException 读取失败
     */
    public Map<String, CountryEntry> parseCountryInfo(InputStream input) throws IOException {
        Map<String, CountryEntry> result = new HashMap<>();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(input, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                if (line.isBlank() || line.startsWith("#")) {
                    continue;
                }
                String[] cols = line.split("\\t");
                if (cols.length < 17) {
                    continue;
                }
                try {
                    result.put(cols[0], new CountryEntry(Long.parseLong(cols[16]), cols[4]));
                } catch (NumberFormatException ignored) {
                    logSkip("countryInfo", cols[0]);
                }
            }
        }
        return result;
    }

    /**
     * 流式解析 alternateNamesV2.txt，仅回传中文候选（zh / zh-*）。
     *
     * @param input 文件输入流
     * @param handler 单行回调
     * @throws IOException 读取失败
     */
    public void streamAlternateNames(InputStream input, AlternateNameHandler handler) throws IOException {
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(input, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                String[] cols = line.split("\\t");
                if (cols.length < 4) {
                    continue;
                }
                String language = cols[2];
                boolean chineseLanguage = language.equals("zh")
                        || language.startsWith("zh-")
                        || language.startsWith("zh_");
                if (!chineseLanguage) {
                    continue;
                }
                try {
                    handler.handle(new AlternateName(
                            Long.parseLong(cols[1]),
                            language,
                            cols[3],
                            cols.length > 4 && "1".equals(cols[4]),
                            cols.length > 7 && "1".equals(cols[7])));
                } catch (NumberFormatException ignored) {
                    logSkip("alternateNamesV2", cols[1]);
                }
            }
        }
    }

    private static long parseLong(String value) {
        try {
            return Long.parseLong(value);
        } catch (NumberFormatException ex) {
            return 0;
        }
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value;
    }

    private static String firstNotBlank(String... values) {
        for (String value : values) {
            if (value != null && !value.isBlank()) {
                return value.trim();
            }
        }
        return null;
    }

    private void logSkip(String file, String key) {
        // GeoNames dump 存在少量脏行，跳过并记录关键信息即可，不中断导入。
        log.debug("跳过无法解析的 GeoNames 行: file={}, key={}", file, key);
    }
}
