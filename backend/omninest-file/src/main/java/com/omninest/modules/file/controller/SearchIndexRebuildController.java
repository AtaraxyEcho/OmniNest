package com.omninest.modules.file.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.file.service.SearchIndexRebuildService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 全站搜索索引重建控制器。
 *
 * <p>重建需要遍历 File 模块的文件节点，索引编排因此归属 File 模块，接口路径保持
 * {@code /api/v1/search/rebuild} 不变，客户端无需感知实现位置。</p>
 */
@Tag(name = "搜索", description = "全文搜索接口")
@RestController
@RequestMapping("/api/v1/search")
@RequiredArgsConstructor
public class SearchIndexRebuildController {

    private final SearchIndexRebuildService searchIndexRebuildService;
    private final CurrentUserContext currentUserContext;

    /**
     * 管理员触发全站搜索索引重建：受理后异步清空索引并按存量文件重新派发，接口只返回任务 ID。
     */
    @Operation(summary = "重建搜索索引",
            description = "管理员触发全站搜索索引重建，返回 taskId，按 /api/v1/tasks/{taskId} 轮询进度")
    @PostMapping("/rebuild")
    @PreAuthorize("hasAuthority('" + Permissions.SYSTEM_CONFIG_MANAGE + "')")
    ApiResponse<Map<String, Object>> rebuildIndex() {
        UUID taskId = searchIndexRebuildService.start(currentUserContext.requireCurrentUserId());
        return ApiResponse.success(Map.of(
                "taskId", taskId.toString(),
                "message", "全站索引重建已受理，正在按存量文件与照片重新派发索引任务"
        ));
    }
}
