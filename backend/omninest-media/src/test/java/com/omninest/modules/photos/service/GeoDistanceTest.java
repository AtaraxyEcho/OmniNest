package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.within;
import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

/** Haversine 球面距离测试：确保不退化为平面度数差。 */
class GeoDistanceTest {

    @Test
    void oneDegreeLatitudeIsAbout111Km() {
        double distance = GeoDistance.haversineKm(30.0, 120.0, Math.toRadians(31.0), Math.toRadians(120.0));
        assertEquals(111.19, distance, 0.5);
    }

    @Test
    void oneDegreeLongitudeAtEquatorIsAbout111Km() {
        double distance = GeoDistance.haversineKm(0.0, 120.0, Math.toRadians(0.0), Math.toRadians(121.0));
        assertEquals(111.32, distance, 0.5);
    }

    @Test
    void longitudeDistanceShrinksWithLatitude() {
        double atEquator = GeoDistance.haversineKm(0.0, 120.0, Math.toRadians(0.0), Math.toRadians(121.0));
        double atLatitude60 = GeoDistance.haversineKm(60.0, 120.0, Math.toRadians(60.0), Math.toRadians(121.0));
        // 纬度 60° 处 1° 经度约为赤道的一半，平面近似无法体现该收缩。
        org.assertj.core.api.Assertions.assertThat(atLatitude60)
                .isCloseTo(atEquator / 2, within(1.0));
    }

    @Test
    void antimeridianDistanceUsesGreatCircle() {
        double distance = GeoDistance.haversineKm(0.0, 179.5, Math.toRadians(0.0), Math.toRadians(-179.5));
        assertEquals(111.32, distance, 0.5);
    }

    @Test
    void samePointIsZero() {
        double distance = GeoDistance.haversineKm(23.13, 113.26, Math.toRadians(23.13), Math.toRadians(113.26));
        assertEquals(0.0, distance, 1e-9);
    }
}
