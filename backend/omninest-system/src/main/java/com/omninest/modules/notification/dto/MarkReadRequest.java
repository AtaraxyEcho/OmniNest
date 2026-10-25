package com.omninest.modules.notification.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.util.List;
import java.util.UUID;

/**
 * 批量标记通知已读请求。
 *
 * <p>单次上限 500 条：通知页按页加载，超过该数量只可能来自异常客户端，
 * 放行会撞上 PostgreSQL 绑定参数上限并占用大量内存。</p>
 *
 * @param ids 通知标识列表
 * @author OmniNest
 */
public record MarkReadRequest(
        @NotNull
        @Size(max = 500)
        List<@NotNull UUID> ids
) {
}
