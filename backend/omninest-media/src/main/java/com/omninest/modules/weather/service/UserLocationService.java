package com.omninest.modules.weather.service;

import com.omninest.modules.weather.service.UserLocationStore.UserLocationSnapshot;
import java.time.Duration;
import java.time.Instant;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 管理用户最近上报的地理位置。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class UserLocationService {

    private static final Duration LOCATION_TTL = Duration.ofDays(7);

    private final UserLocationStore locationStore;

    /**
     * 保存用户最近上报的位置。
     *
     * @param userId 用户标识
     * @param lat 纬度
     * @param lon 经度
     * @param source 上报来源
     */
    public void saveLocation(UUID userId, double lat, double lon, String source) {
        locationStore.save(
                userId,
                new UserLocationSnapshot(WeatherCoordinates.format(lon, lat), source, Instant.now()),
                LOCATION_TTL
        );
    }

    /**
     * 查询用户最近上报的经纬度。
     *
     * @param userId 用户标识
     * @return 经度和纬度文本，不存在时返回 {@code null}
     */
    public String getLocation(UUID userId) {
        if (userId == null) {
            return null;
        }
        return locationStore.find(userId)
                .map(UserLocationSnapshot::latLon)
                .orElse(null);
    }
}
