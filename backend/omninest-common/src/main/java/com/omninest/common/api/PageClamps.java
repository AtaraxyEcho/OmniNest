package com.omninest.common.api;

/**
 * 列表分页参数夹取。
 */
public final class PageClamps {

    public static final int MAX_SIZE = 200;
    public static final int DEFAULT_SIZE = 20;

    private PageClamps() {
    }

    public static int safePage(int page) {
        return Math.max(0, page);
    }

    public static int safeSize(int size) {
        return safeSize(size, MAX_SIZE);
    }

    /**
     * 按域上限夹取每页数量。
     *
     * @param size 请求每页数量
     * @param maxSize 该域允许的最大每页数量
     * @return 夹取后的每页数量
     */
    public static int safeSize(int size, int maxSize) {
        int limit = Math.min(Math.max(1, maxSize), MAX_SIZE);
        return Math.min(Math.max(1, size <= 0 ? DEFAULT_SIZE : size), limit);
    }

    public static int safeLimit(int limit, int defaultLimit) {
        return Math.min(Math.max(1, limit <= 0 ? defaultLimit : limit), MAX_SIZE);
    }
}
