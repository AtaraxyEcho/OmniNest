package com.omninest.modules.sync.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.sync.dto.SyncDtos.SyncBootstrapDto;
import com.omninest.modules.sync.dto.SyncDtos.SyncEventPageDto;
import com.omninest.modules.sync.dto.SyncDtos.SyncHeadDto;
import com.omninest.modules.sync.service.SyncEventQueryService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * 全平台用户数据同步接口。
 *
 * @author OmniNest
 */
@RestController
@RequiredArgsConstructor
@ConditionalOnProperty(
        prefix = "omninest.runtime",
        name = "role",
        havingValue = "api",
        matchIfMissing = true
)
@Tag(name = "数据同步", description = "全平台数据同步游标与事件补偿")
public class SyncController {

    private final CurrentUserContext currentUserContext;
    private final SyncEventQueryService syncEventQueryService;

    /**
     * 获取客户端首次同步使用的高水位。
     *
     * @return 同步初始化数据
     */
    @Operation(summary = "初始化同步游标", description = "获取当前服务端同步高水位和事件保留水位")
    @GetMapping("/api/v1/sync/bootstrap")
    @PreAuthorize("hasAuthority('" + Permissions.PROFILE_READ + "')")
    ApiResponse<SyncBootstrapDto> bootstrap() {
        currentUserContext.requireCurrentUserId();
        return ApiResponse.success(syncEventQueryService.bootstrap());
    }

    /**
     * 按游标查询当前用户可见的同步事件。
     *
     * @param after 起始游标，不包含
     * @param limit 最大返回数量
     * @return 同步事件增量页
     */
    @Operation(summary = "查询增量同步事件", description = "按全局游标升序查询当前用户可见的事件")
    @GetMapping("/api/v1/sync/events")
    @PreAuthorize("hasAuthority('" + Permissions.PROFILE_READ + "')")
    ApiResponse<SyncEventPageDto> events(
            @RequestParam(defaultValue = "0") long after,
            @RequestParam(defaultValue = "200") int limit
    ) {
        UUID userId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(syncEventQueryService.events(userId, after, limit));
    }

    /**
     * 获取用于低频校验的同步高水位。
     *
     * @return 同步高水位
     */
    @Operation(summary = "查询同步高水位", description = "获取低频链路校验使用的同步高水位")
    @GetMapping("/api/v1/sync/head")
    @PreAuthorize("hasAuthority('" + Permissions.PROFILE_READ + "')")
    ApiResponse<SyncHeadDto> head() {
        currentUserContext.requireCurrentUserId();
        return ApiResponse.success(syncEventQueryService.head());
    }
}
