package com.omninest.common.api;

import java.util.List;

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

    /**
     * 从内存列表切出请求页窗口。
     *
     * <p>只用于结果集已在内存、无法下推数据库分页的小列表；越界页返回空列表，
     * 总数由调用方按整表条数上报。</p>
     *
     * @param items 全量列表
     * @param page 页码，从零开始
     * @param size 每页数量
     * @return 当前页窗口
     */
    public static <T> List<T> slice(List<T> items, int page, int size) {
        if (items == null || items.isEmpty()) {
            return List.of();
        }
        long from = (long) safePage(page) * safeSize(size);
        if (from >= items.size()) {
            return List.of();
        }
        int start = (int) from;
        return items.subList(start, (int) Math.min(from + safeSize(size), items.size()));
    }
}
