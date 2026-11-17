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
     * 按域上限与该域默认页大小夹取每页数量。
     *
     * <p>{@code size} 非正表示客户端没有给出有效值，按调用方声明的域默认值处理。控制器同时
     * 用 {@code defaultValue} 声明缺省值时，两处必须落到同一个数：否则同一个接口会出现
     * "不传是 100 条、传 0 是 20 条"的两种默认。</p>
     *
     * @param size 请求每页数量
     * @param maxSize 该域允许的最大每页数量，超过全局 {@link #MAX_SIZE} 时按全局上限
     * @param defaultSize 该域默认每页数量
     * @return 夹取后的每页数量
     */
    public static int safeSize(int size, int maxSize, int defaultSize) {
        int limit = Math.min(Math.max(1, maxSize), MAX_SIZE);
        int fallback = Math.min(Math.max(1, defaultSize), limit);
        return Math.min(Math.max(1, size <= 0 ? fallback : size), limit);
    }

    /**
     * 按域上限夹取每页数量；非正数按全局默认 {@link #DEFAULT_SIZE} 处理。
     *
     * @param size 请求每页数量
     * @param maxSize 该域允许的最大每页数量
     * @return 夹取后的每页数量
     */
    public static int safeSize(int size, int maxSize) {
        return safeSize(size, maxSize, DEFAULT_SIZE);
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

    /**
     * 按夹取后的分页参数切出内存列表并组装响应。
     *
     * <p>响应体的 page、size 与 totalPages 必须与切片实际使用的参数同源，否则请求带上越界或
     * 负数分页参数时，客户端读到的页码与收到的条目对不上，翻页会跳页或提前判定结束。</p>
     *
     * @param items 全量列表
     * @param page 请求页码，从零开始
     * @param size 请求每页数量
     * @return 当前页响应
     */
    public static <T> PageResponse<T> pagedResponse(List<T> items, int page, int size) {
        int safePage = safePage(page);
        int safeSize = safeSize(size);
        long totalElements = items == null ? 0L : items.size();
        return PageResponse.of(slice(items, safePage, safeSize), safePage, safeSize, totalElements);
    }
}
