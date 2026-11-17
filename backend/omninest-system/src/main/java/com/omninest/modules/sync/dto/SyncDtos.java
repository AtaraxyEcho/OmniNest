package com.omninest.modules.sync.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * 用户数据同步接口 DTO 集合。
 *
 * @author OmniNest
 */
@Schema(description = "用户数据同步 DTO 集合")
public final class SyncDtos {

    private SyncDtos() {
    }

    /**
     * 客户端可见的同步事件。
     *
     * @param schemaVersion 契约版本
     * @param eventId 事件标识
     * @param sequenceNo 全局事件序号
     * @param scope 业务作用域
     * @param resourceType 资源类型
     * @param resourceId 资源标识
     * @param action 事件动作
     * @param resourceVersion 资源版本
     * @param hints 非敏感刷新提示
     * @param occurredAt 事件发生时间
     */
    @Schema(description = "客户端可见的同步事件")
    public record SyncEventDto(
            int schemaVersion,
            UUID eventId,
            long sequenceNo,
            String scope,
            String resourceType,
            String resourceId,
            String action,
            Long resourceVersion,
            Map<String, Object> hints,
            Instant occurredAt
    ) {
    }

    /**
     * 客户端首次建立同步状态时使用的高水位。
     *
     * @param schemaVersion 契约版本
     * @param latestCursor 全局最新游标
     * @param retentionFloor 已清理事件的最大游标
     * @param serverTime 服务端时间
     */
    @Schema(description = "同步初始化高水位")
    public record SyncBootstrapDto(
            int schemaVersion,
            long latestCursor,
            long retentionFloor,
            Instant serverTime
    ) {
    }

    /**
     * 按游标查询的同步事件页。
     *
     * @param items 当前用户可见事件
     * @param nextCursor 下一次请求使用的游标
     * @param latestCursor 本次查询固定的全局高水位
     * @param hasMore 是否仍有后续事件
     * @param resetRequired 是否必须执行全量失效恢复
     */
    @Schema(description = "同步事件增量页")
    public record SyncEventPageDto(
            List<SyncEventDto> items,
            long nextCursor,
            long latestCursor,
            boolean hasMore,
            boolean resetRequired
    ) {
    }

    /**
     * 同步链路轻量高水位。
     *
     * @param schemaVersion 契约版本
     * @param latestCursor 全局最新游标
     * @param retentionFloor 已清理事件的最大游标
     */
    @Schema(description = "同步链路高水位")
    public record SyncHeadDto(
            int schemaVersion,
            long latestCursor,
            long retentionFloor
    ) {
    }
}
