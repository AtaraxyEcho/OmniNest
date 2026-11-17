package com.omninest.modules.photos.service;

/**
 * 球面距离计算工具。
 *
 * <p>统一使用 Haversine 公式（atan2 形式），地球平均半径 6371.0088 公里。
 * 弧度重载供内存索引扫描使用，避免对查询点坐标的重复三角计算。</p>
 *
 * @author OmniNest
 */
public final class GeoDistance {

    /** 地球平均半径（公里）；同包索引扫描用它做纬距下界剪枝。 */
    static final double EARTH_RADIUS_KM = 6371.0088;

    private GeoDistance() {
    }

    /**
     * 计算两点球面距离（度数入参）。
     *
     * @param latitude1 点 1 纬度（度）
     * @param longitude1 点 1 经度（度）
     * @param latitude2Radians 点 2 纬度（弧度，快照预计算值）
     * @param longitude2Radians 点 2 经度（弧度，快照预计算值）
     * @return 距离（公里）
     */
    public static double haversineKm(
            double latitude1,
            double longitude1,
            double latitude2Radians,
            double longitude2Radians) {
        return haversineKmRadians(
                Math.toRadians(latitude1),
                Math.toRadians(longitude1),
                latitude2Radians,
                longitude2Radians);
    }

    /**
     * 计算两点球面距离（弧度入参）。
     *
     * @param latitude1Radians 点 1 纬度（弧度）
     * @param longitude1Radians 点 1 经度（弧度）
     * @param latitude2Radians 点 2 纬度（弧度）
     * @param longitude2Radians 点 2 经度（弧度）
     * @return 距离（公里）
     */
    public static double haversineKmRadians(
            double latitude1Radians,
            double longitude1Radians,
            double latitude2Radians,
            double longitude2Radians) {
        double deltaLatitude = latitude2Radians - latitude1Radians;
        double deltaLongitude = longitude2Radians - longitude1Radians;
        double sinHalfLatitude = Math.sin(deltaLatitude / 2);
        double sinHalfLongitude = Math.sin(deltaLongitude / 2);
        double a = sinHalfLatitude * sinHalfLatitude
                + Math.cos(latitude1Radians) * Math.cos(latitude2Radians)
                        * sinHalfLongitude * sinHalfLongitude;
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return EARTH_RADIUS_KM * c;
    }
}
