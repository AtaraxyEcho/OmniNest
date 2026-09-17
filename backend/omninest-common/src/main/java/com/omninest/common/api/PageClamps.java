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
        return Math.min(Math.max(1, size <= 0 ? DEFAULT_SIZE : size), MAX_SIZE);
    }

    public static int safeLimit(int limit, int defaultLimit) {
        return Math.min(Math.max(1, limit <= 0 ? defaultLimit : limit), MAX_SIZE);
    }
}
