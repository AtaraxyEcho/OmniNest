package com.omninest.modules.photos.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Arrays;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

/** 双语位置格式化测试：同一命中产出中英两份展示字段。 */
class GeoLocationFormatterTest {

    private static GeoCitySnapshot.Entry guangzhou() {
        return new GeoCitySnapshot.Entry(
                1809858,
                "Guangzhou",
                "广州市",
                "CN",
                "China",
                "中国",
                "Guangdong",
                "广东省",
                Math.toRadians(23.13),
                Math.toRadians(113.26));
    }

    @Test
    void producesBilingualFieldsFromSameMatch() {
        GeoCityMatch match = new GeoCityMatch(guangzhou(), 8.73456);
        Map<String, Object> result = GeoLocationFormatter.toGpsLocation(match);

        assertEquals("Guangzhou", result.get("city"));
        assertEquals("广州市", result.get("cityZh"));
        assertEquals("Guangdong", result.get("state"));
        assertEquals("广东省", result.get("stateZh"));
        assertEquals("China", result.get("country"));
        assertEquals("中国", result.get("countryZh"));
        assertEquals("China · Guangdong · Guangzhou", result.get("displayName"));
        assertEquals("中国 · 广东省 · 广州市", result.get("displayNameZh"));
        assertEquals(1809858L, result.get("geonameId"));
        assertEquals(8.73, (double) result.get("distanceKm"), 1e-9);
        assertEquals("geonames", result.get("geocoder"));
    }

    @Test
    void sameMatchKeepsStableGeonameIdAndDistance() {
        GeoCityMatch match = new GeoCityMatch(guangzhou(), 3.21);
        Map<String, Object> first = GeoLocationFormatter.toGpsLocation(match);
        Map<String, Object> second = GeoLocationFormatter.toGpsLocation(match);
        assertEquals(first.get("geonameId"), second.get("geonameId"));
        assertEquals(first.get("distanceKm"), second.get("distanceKm"));
        assertTrue(first.containsKey("displayNameZh"));
        assertFalse(first.containsKey("district"));
    }

    @Test
    void missingSegmentsAreSkippedInDisplayName() {
        GeoCitySnapshot.Entry city = new GeoCitySnapshot.Entry(
                42, "Nowhere", null, "US", "United States", null, null, null,
                Math.toRadians(40.0), Math.toRadians(-74.0));
        GeoCityMatch match = new GeoCityMatch(city, 1.0);
        Map<String, Object> result = GeoLocationFormatter.toGpsLocation(match);
        assertEquals("United States · Nowhere", result.get("displayName"));
        assertFalse(result.containsKey("displayNameZh"));
        assertFalse(result.containsKey("stateZh"));
    }

    @Test
    void displayNameJoinsWithMiddleDotSeparator() {
        assertEquals("A · B · C", GeoLocationFormatter.displayName(Arrays.asList("A", null, "B", " ", "C")));
    }
}
