package com.omninest.modules.search.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.search.dto.SearchResultDto;
import com.omninest.modules.search.service.FileSearchService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequiredArgsConstructor
@Tag(name = "搜索", description = "全文搜索接口")
public class SearchController {
    private final FileSearchService fileSearchService;
    private final CurrentUserContext currentUserContext;

    @Operation(summary = "全文搜索",
            description = "根据关键词搜索当前用户的个人空间与可见的共享空间文件；spaceType 可按空间过滤")
    @GetMapping("/api/v1/search")
    @PreAuthorize("hasAuthority('" + Permissions.FILE_READ + "')")
    ApiResponse<List<SearchResultDto>> search(
            @RequestParam String q,
            @RequestParam(required = false) String spaceType) {
        UUID ownerUserId = currentUserContext.requireCurrentUserId();
        return ApiResponse.success(fileSearchService.search(ownerUserId, q, spaceType));
    }
}
