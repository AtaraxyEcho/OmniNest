package com.omninest.modules.photos.service;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.when;

import com.omninest.common.ratelimit.RateLimitService;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

/** 离线优先逆地理编码服务测试：双语输出、距离阈值、Nominatim 开关与指标。 */
class PhotoGeoServiceTest {

    private PhotosRuntimeConfigService configService;
    private GeoCityIndex geoCityIndex;
    private MeterRegistry meterRegistry;
    private PhotoGeoService service;

    @BeforeEach
    void setUp() {
        configService = Mockito.mock(PhotosRuntimeConfigService.class);
        geoCityIndex = Mockito.mock(GeoCityIndex.class);
        NominatimRateLimiter rateLimiter = Mockito.mock(NominatimRateLimiter.class);
        RateLimitService distributedRateLimiter = Mockito.mock(RateLimitService.class);
        meterRegistry = new SimpleMeterRegistry();

        when(configService.isGeoOfflineEnabled()).thenReturn(true);
        when(configService.geoMaxDistanceKm()).thenReturn(100);
        when(configService.isNominatimEnabled()).thenReturn(false);

        service = new PhotoGeoService(
                configService,
                rateLimiter,
                distributedRateLimiter,
                meterRegistry,
                geoCityIndex);
    }

    private GeoCitySnapshot snapshotWithNearCity() {
        return GeoCitySnapshot.of("v1", List.of(new GeoCitySnapshot.Entry(
                1809858, "Guangzhou", "广州市", "CN", "China", "中国",
                "Guangdong", "广东省",
                Math.toRadians(23.13), Math.toRadians(113.26))));
    }

    @Test
    void offlineHitProducesBilingualGpsLocation() {
        when(geoCityIndex.currentSnapshot()).thenReturn(snapshotWithNearCity());

        Map<String, Object> result = service.reverseGeocode(
                BigDecimal.valueOf(23.14), BigDecimal.valueOf(113.27));

        assertEquals("Guangzhou", result.get("city"));
        assertEquals("广州市", result.get("cityZh"));
        assertEquals("中国 · 广东省 · 广州市", result.get("displayNameZh"));
        assertEquals("China · Guangdong · Guangzhou", result.get("displayName"));
        assertEquals(1809858L, result.get("geonameId"));
        assertEquals("geonames", result.get("geocoder"));
        assertEquals(1.0, meterRegistry.counter("photo.geo.offline.success").count(), 1e-9);
    }

    @Test
    void beyondThresholdProducesEmptyWithoutNominatim() {
        when(geoCityIndex.currentSnapshot()).thenReturn(snapshotWithNearCity());

        Map<String, Object> result = service.reverseGeocode(
                BigDecimal.valueOf(10.0), BigDecimal.valueOf(20.0));

        assertTrue(result.isEmpty());
        assertEquals(1.0, meterRegistry.counter("photo.geo.distance.rejected").count(), 1e-9);
        assertEquals(0.0, meterRegistry.counter("photo.geo.nominatim.fallback").count(), 1e-9);
    }

    @Test
    void invalidCoordinateIsRejected() {
        assertEquals(Map.of(), service.reverseGeocode(null, BigDecimal.valueOf(113.26)));
        assertEquals(Map.of(), service.reverseGeocode(
                BigDecimal.valueOf(95.0), BigDecimal.valueOf(113.26)));
        assertEquals(2.0, meterRegistry.counter("photo.geo.invalid.coordinate").count(), 1e-9);
    }

    @Test
    void emptyIndexFallsThroughToNominatimSwitch() {
        when(geoCityIndex.currentSnapshot()).thenReturn(GeoCitySnapshot.EMPTY);

        Map<String, Object> result = service.reverseGeocode(
                BigDecimal.valueOf(23.14), BigDecimal.valueOf(113.27));

        assertTrue(result.isEmpty());
        assertEquals(1.0, meterRegistry.counter("photo.geo.no.index").count(), 1e-9);
    }

    @Test
    void disabledOfflineSkipsIndexAndReturnsEmptyWhenNominatimOff() {
        when(configService.isGeoOfflineEnabled()).thenReturn(false);
        when(geoCityIndex.currentSnapshot()).thenReturn(snapshotWithNearCity());

        Map<String, Object> result = service.reverseGeocode(
                BigDecimal.valueOf(23.14), BigDecimal.valueOf(113.27));

        assertTrue(result.isEmpty());
        assertEquals(0.0, meterRegistry.counter("photo.geo.offline.success").count(), 1e-9);
    }

    @Test
    void pinnedSnapshotOverridesCurrentIndex() {
        when(geoCityIndex.currentSnapshot()).thenReturn(GeoCitySnapshot.EMPTY);

        Map<String, Object> result = service.reverseGeocode(
                snapshotWithNearCity(),
                BigDecimal.valueOf(23.14), BigDecimal.valueOf(113.27));

        assertEquals("广州市", result.get("cityZh"));
        assertEquals(1.0, meterRegistry.counter("photo.geo.offline.success").count(), 1e-9);
    }
}
