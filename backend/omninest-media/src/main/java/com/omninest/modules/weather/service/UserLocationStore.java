package com.omninest.modules.weather.service;

import java.time.Duration;
import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

/**
 * 定义用户最近上报位置的存取契约。
 *
 * @author OmniNest
 */
public interface UserLocationStore {

    /**
     * 保存用户最近上报的位置快照。
     *
     * @param userId 用户标识
     * @param location 位置快照
     * @param ttl 快照有效期
     */
    void save(UUID userId, UserLocationSnapshot location, Duration ttl);

    /**
     * 查询用户最近上报的位置快照。
     *
     * @param userId 用户标识
     * @return 位置快照
     */
    Optional<UserLocationSnapshot> find(UUID userId);

    /**
     * 用户位置快照。
     *
     * @param latLon 经度和纬度文本
     * @param source 上报来源
     * @param reportedAt 上报时间
     */
    record UserLocationSnapshot(String latLon, String source, Instant reportedAt) {
    }
}
