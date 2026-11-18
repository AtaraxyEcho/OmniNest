package com.omninest.modules.user.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.util.List;
import java.util.Map;

/**
 * 管理端运行日志页与当前缓存筛选元数据。
 *
 * @param items 当前页记录
 * @param page 从零开始的页码
 * @param size 页面容量
 * @param totalElements 筛选后记录数
 * @param totalPages 总页数
 * @param levelCounts 缓存中各级别的记录数
 * @param sources 缓存中出现的记录器名称
 */
@Schema(description = "管理端运行日志分页")
public record AdminSystemLogPageDto(
        List<AdminSystemLogDto> items,
        int page,
        int size,
        long totalElements,
        int totalPages,
        Map<String, Long> levelCounts,
        List<String> sources
) {
    public AdminSystemLogPageDto {
        items = List.copyOf(items);
        levelCounts = Map.copyOf(levelCounts);
        sources = List.copyOf(sources);
    }
}
