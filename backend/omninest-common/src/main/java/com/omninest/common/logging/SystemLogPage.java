package com.omninest.common.logging;

import java.util.List;
import java.util.Map;

/**
 * 运行日志筛选页。
 *
 * @param items 当前页记录
 * @param page 从零开始的页码
 * @param size 页面容量
 * @param totalElements 筛选后总记录数
 */
public record SystemLogPage(
        List<SystemLogEntry> items,
        int page,
        int size,
        long totalElements,
        Map<String, Long> levelCounts,
        List<String> sources
) {
    public SystemLogPage {
        items = List.copyOf(items);
        levelCounts = Map.copyOf(levelCounts);
        sources = List.copyOf(sources);
    }
}
