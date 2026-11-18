package com.omninest.modules.user.service;

import com.omninest.common.logging.SystemLogEntry;
import com.omninest.common.logging.SystemLogPage;
import com.omninest.common.logging.SystemLogQuery;
import com.omninest.modules.user.dto.AdminSystemLogDto;
import com.omninest.modules.user.dto.AdminSystemLogPageDto;
import java.util.List;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 管理端系统日志查询服务。
 */
@Service
@RequiredArgsConstructor
public class AdminSystemLogService {
    private final SystemLogQuery systemLogQuery;

    /**
     * 查询当前 API 进程的最近运行日志。
     *
     * @param page 从零开始的页码
     * @param size 页面容量
     * @param level 级别筛选
     * @param source 来源筛选
     * @param query 消息关键字
     * @return 最新优先的日志页
     */
    public AdminSystemLogPageDto page(
            int page,
            int size,
            String level,
            String source,
            String query
    ) {
        SystemLogPage result = systemLogQuery.search(query, level, source, page, size);
        List<AdminSystemLogDto> items = result.items().stream()
                .map(this::toDto)
                .toList();
        int totalPages = result.size() <= 0
                ? 0
                : (int) Math.ceil((double) result.totalElements() / result.size());
        return new AdminSystemLogPageDto(
                items,
                result.page(),
                result.size(),
                result.totalElements(),
                totalPages,
                result.levelCounts(),
                result.sources()
        );
    }

    private AdminSystemLogDto toDto(SystemLogEntry entry) {
        return new AdminSystemLogDto(
                entry.id(),
                entry.timestamp(),
                entry.level(),
                entry.source(),
                entry.message()
        );
    }
}
