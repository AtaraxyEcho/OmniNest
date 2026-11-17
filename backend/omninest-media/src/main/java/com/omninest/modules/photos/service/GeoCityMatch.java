package com.omninest.modules.photos.service;

/**
 * 最近城市命中结果。
 *
 * @param city 命中的城市快照条目
 * @param distanceKm 与城市的球面距离（公里）
 * @author OmniNest
 */
public record GeoCityMatch(GeoCitySnapshot.Entry city, double distanceKm) {
}
