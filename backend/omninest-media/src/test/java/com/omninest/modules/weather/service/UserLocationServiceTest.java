package com.omninest.modules.weather.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.omninest.modules.weather.service.UserLocationStore.UserLocationSnapshot;
import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;

/**
 * 验证用户最近位置的保存和查询行为。
 *
 * @author OmniNest
 */
class UserLocationServiceTest {

    private static final UUID USER_ID = UUID.fromString("10000000-0000-0000-0000-000000000001");

    private final UserLocationStore locationStore = Mockito.mock(UserLocationStore.class);
    private final UserLocationService service = new UserLocationService(locationStore);

    @Test
    void saveLocationStoresNormalizedSnapshotForSevenDays() {
        Instant beforeSave = Instant.now();

        service.saveLocation(USER_ID, 31.2304, 121.4737, "device");

        ArgumentCaptor<UserLocationSnapshot> snapshotCaptor =
                ArgumentCaptor.forClass(UserLocationSnapshot.class);
        verify(locationStore).save(
                Mockito.eq(USER_ID),
                snapshotCaptor.capture(),
                Mockito.eq(Duration.ofDays(7))
        );
        // 坐标统一按两位小数落库：既是天气缓存键，也避免极小坐标输出科学计数法。
        assertThat(snapshotCaptor.getValue().latLon()).isEqualTo("121.47,31.23");
        assertThat(snapshotCaptor.getValue().source()).isEqualTo("device");
        assertThat(snapshotCaptor.getValue().reportedAt()).isAfterOrEqualTo(beforeSave);
    }

    @Test
    void getLocationReturnsLatestCoordinates() {
        when(locationStore.find(USER_ID)).thenReturn(Optional.of(
                new UserLocationSnapshot("121.4737,31.2304", "device", Instant.now())
        ));

        assertThat(service.getLocation(USER_ID)).isEqualTo("121.4737,31.2304");
    }
}
