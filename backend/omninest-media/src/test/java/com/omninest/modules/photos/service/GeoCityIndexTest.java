package com.omninest.modules.photos.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.omninest.common.error.BusinessException;
import com.omninest.modules.photos.domain.GeoDataset;
import com.omninest.modules.photos.repository.GeoCityRepository;
import com.omninest.modules.photos.repository.GeoDatasetRepository;
import java.math.BigDecimal;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;

/** GeoNames 离线索引单元测试：最近城市、GPS 校验、快照原子切换。 */
class GeoCityIndexTest {

    private GeoCityRepository cityRepository;
    private GeoDatasetRepository datasetRepository;
    private GeoCityIndex index;

    private static GeoCityRepository.GeoCityRow row(
            long geonameId,
            String name,
            String nameZh,
            String countryNameEn,
            String countryNameZh,
            String provinceNameEn,
            String provinceNameZh,
            double latitude,
            double longitude) {
        return new GeoCityRepository.GeoCityRow() {
            @Override
            public Long getGeonameId() {
                return geonameId;
            }

            @Override
            public String getName() {
                return name;
            }

            @Override
            public String getNameZh() {
                return nameZh;
            }

            @Override
            public String getCountryCode() {
                return "CN";
            }

            @Override
            public String getCountryNameEn() {
                return countryNameEn;
            }

            @Override
            public String getCountryNameZh() {
                return countryNameZh;
            }

            @Override
            public String getProvinceNameEn() {
                return provinceNameEn;
            }

            @Override
            public String getProvinceNameZh() {
                return provinceNameZh;
            }

            @Override
            public BigDecimal getLatitude() {
                return BigDecimal.valueOf(latitude);
            }

            @Override
            public BigDecimal getLongitude() {
                return BigDecimal.valueOf(longitude);
            }
        };
    }

    @BeforeEach
    void setUp() {
        cityRepository = Mockito.mock(GeoCityRepository.class);
        datasetRepository = Mockito.mock(GeoDatasetRepository.class);
        index = new GeoCityIndex(cityRepository, datasetRepository);
    }

    private GeoDataset publishedDataset(String version) {
        GeoDataset dataset = new GeoDataset();
        dataset.setId(UUID.randomUUID());
        dataset.setDatasetVersion(version);
        dataset.setStatus(GeoDataset.STATUS_PUBLISHED);
        return dataset;
    }

    private void stubStartupWithThreeCities(String version) {
        GeoDataset dataset = publishedDataset(version);
        Mockito.when(datasetRepository.findFirstByStatusOrderByPublishedAtDesc(GeoDataset.STATUS_PUBLISHED))
                .thenReturn(Optional.of(dataset));
        Mockito.when(cityRepository.findRowsByDatasetId(dataset.getId()))
                .thenReturn(List.of(
                        row(1, "Hangzhou", "杭州市", "China", "中国", "Zhejiang", "浙江省", 30.2741, 120.1551),
                        row(2, "Shanghai", "上海市", "China", "中国", "Shanghai", "上海市", 31.2304, 121.4737),
                        row(3, "Beijing", "北京市", "China", "中国", "Beijing", "北京市", 39.9042, 116.4074)));
        index.loadOnStartup();
    }

    @Test
    void startupLoadsPublishedSnapshotAndNearestReturnsClosestCity() {
        stubStartupWithThreeCities("2026-09-05-cities5000-001");
        assertEquals("2026-09-05-cities5000-001", index.currentSnapshot().datasetVersion());

        Optional<GeoCityMatch> nearest = index.nearest(31.13, 121.48);
        assertTrue(nearest.isPresent());
        assertEquals(2, nearest.get().city().geonameId());
        assertEquals("上海市", nearest.get().city().nameZh());
        assertEquals("上海市", nearest.get().city().provinceNameZh());
        assertThat(nearest.get().distanceKm()).isLessThan(20);
    }

    @Test
    void startupWithoutPublishedDatasetKeepsEmptyIndex() {
        Mockito.when(datasetRepository.findFirstByStatusOrderByPublishedAtDesc(GeoDataset.STATUS_PUBLISHED))
                .thenReturn(Optional.empty());
        index.loadOnStartup();
        assertTrue(index.nearest(31.13, 121.48).isEmpty());
    }

    @Test
    void invalidCoordinatesReturnEmpty() {
        stubStartupWithThreeCities("v1");
        assertTrue(index.nearest(Double.NaN, 121.48).isEmpty());
        assertTrue(index.nearest(31.13, Double.POSITIVE_INFINITY).isEmpty());
        assertTrue(index.nearest(91.0, 121.48).isEmpty());
        assertTrue(index.nearest(-91.0, 121.48).isEmpty());
        assertTrue(index.nearest(31.13, -181.0).isEmpty());
        assertTrue(index.nearest(31.13, 181.0).isEmpty());
        assertTrue(index.nearest(31.13, 121.48).isPresent());
    }

    @Test
    void reloadToVersionSwapsSnapshotAtomically() {
        stubStartupWithThreeCities("v1");
        assertTrue(index.nearest(39.90, 116.40).isPresent());

        GeoDataset v2 = publishedDataset("v2");
        Mockito.when(datasetRepository.findByDatasetVersion("v2")).thenReturn(Optional.of(v2));
        Mockito.when(cityRepository.findRowsByDatasetId(v2.getId()))
                .thenReturn(List.of());
        index.reloadToVersion("v2");

        assertEquals("v2", index.currentSnapshot().datasetVersion());
        assertTrue(index.nearest(39.90, 116.40).isEmpty());
    }

    @Test
    void reloadToVersionRejectsUnpublishedDataset() {
        GeoDataset draft = new GeoDataset();
        draft.setDatasetVersion("v2");
        draft.setStatus(GeoDataset.STATUS_IMPORTING);
        Mockito.when(datasetRepository.findByDatasetVersion("v2")).thenReturn(Optional.of(draft));
        assertThrows(BusinessException.class, () -> index.reloadToVersion("v2"));
    }

    @Test
    void reloadToVersionRejectsUnknownDataset() {
        Mockito.when(datasetRepository.findByDatasetVersion("missing")).thenReturn(Optional.empty());
        assertThrows(BusinessException.class, () -> index.reloadToVersion("missing"));
    }
}
