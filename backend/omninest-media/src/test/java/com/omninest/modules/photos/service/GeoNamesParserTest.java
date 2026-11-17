package com.omninest.modules.photos.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

/** GeoNames dump 解析器测试：列位、注释行、中文候选过滤。 */
class GeoNamesParserTest {

    private final GeoNamesParser parser = new GeoNamesParser();

    @Test
    void streamCitiesParsesCoreColumns() throws IOException {
        String line = String.join("\t",
                "1809858", "Guangzhou", "Guangzhou", "GZ,Canton", "23.11667", "113.25",
                "P", "PPTA", "CN", "", "30", "", "", "", "15200000", "11", "21", "Asia/Shanghai", "2024-01-01");
        List<GeoNamesParser.CityRow> rows = new ArrayList<>();
        parser.streamCities(new ByteArrayInputStream(line.getBytes(StandardCharsets.UTF_8)), rows::add);

        assertEquals(1, rows.size());
        GeoNamesParser.CityRow row = rows.get(0);
        assertEquals(1809858L, row.geonameId());
        assertEquals("Guangzhou", row.name());
        assertEquals(23.11667, row.latitude().doubleValue(), 1e-6);
        assertEquals(113.25, row.longitude().doubleValue(), 1e-6);
        assertEquals("PPTA", row.featureCode());
        assertEquals("CN", row.countryCode());
        assertEquals("30", row.admin1Code());
        assertEquals(15200000L, row.population());
    }

    @Test
    void streamCitiesSkipsBlankAndMalformedLines() throws IOException {
        String content = "\n#comment\trow\nshort\tline\n";
        List<GeoNamesParser.CityRow> rows = new ArrayList<>();
        parser.streamCities(new ByteArrayInputStream(content.getBytes(StandardCharsets.UTF_8)), rows::add);
        assertTrue(rows.isEmpty());
    }

    @Test
    void admin1CodesUsesLastColumnAsGeonameId() throws IOException {
        String line = "CN.30\tGuangdong Sheng\tGuangdong\t1808702\n";
        Map<String, GeoNamesParser.Admin1Entry> result =
                parser.parseAdmin1Codes(new ByteArrayInputStream(line.getBytes(StandardCharsets.UTF_8)));

        GeoNamesParser.Admin1Entry entry = result.get("CN.30");
        assertEquals(1808702L, entry.geonameId());
        assertEquals("Guangdong", entry.nameEn());
    }

    @Test
    void countryInfoSkipsCommentHeaderAndReadsNameAndGeonameId() throws IOException {
        String content = "#ISO\tISO3\tISO-Numeric\tfips\tCountry\tCapital\n"
                + "CN\tCHN\t156\tCH\tChina\tBeijing\t1367000000\t0\t\t\t\t\t\t\t\t\t1814991\n";
        Map<String, GeoNamesParser.CountryEntry> result =
                parser.parseCountryInfo(new ByteArrayInputStream(content.getBytes(StandardCharsets.UTF_8)));

        GeoNamesParser.CountryEntry entry = result.get("CN");
        assertEquals("China", entry.nameEn());
        assertEquals(1814991L, entry.geonameId());
        assertNull(result.get("#ISO"));
    }

    @Test
    void alternateNamesOnlyStreamsChineseCandidates() throws IOException {
        String content = String.join("\n",
                "10001\t1809858\ten\tCanton\t1\t0\t0\t0\n",
                "10002\t1809858\tzh-Hans\t广州市\t1\t0\t0\t0\n",
                "10003\t1809858\tzh\t广州\t0\t0\t0\t0\n",
                "10004\t1809858\tfr\tGuangzhou\t0\t0\t0\t0\n",
                "bad\trow\n");
        List<GeoNamesParser.AlternateName> candidates = new ArrayList<>();
        parser.streamAlternateNames(
                new ByteArrayInputStream(content.getBytes(StandardCharsets.UTF_8)), candidates::add);

        assertEquals(2, candidates.size());
        assertEquals("zh-Hans", candidates.get(0).language());
        assertTrue(candidates.get(0).preferred());
        assertEquals("zh", candidates.get(1).language());
    }
}
