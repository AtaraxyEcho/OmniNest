package com.omninest.modules.backdrop.controller;

import com.omninest.common.api.ApiResponse;
import com.omninest.common.security.CurrentUserContext;
import com.omninest.common.security.Permissions;
import com.omninest.modules.backdrop.dto.BackdropDtos.BackdropAssetDto;
import com.omninest.modules.backdrop.service.BackdropAssetService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.tags.Tag;
import java.util.List;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.http.MediaType;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/**
 * 背景库接口。
 *
 * @author OmniNest
 */
@RestController
@RequiredArgsConstructor
@Tag(name = "背景库", description = "跨端背景素材库管理")
public class BackdropController {

    private final BackdropAssetService backdropAssetService;
    private final CurrentUserContext currentUserContext;

    /**
     * 查询当前用户的背景素材列表。
     *
     * @return 素材 DTO 列表
     */
    @Operation(summary = "查询背景素材列表", description = "返回当前用户的背景素材与短期签名访问地址")
    @PreAuthorize("hasAuthority('" + Permissions.BACKDROP_READ + "')")
    @GetMapping("/api/v1/backdrops")
    public ApiResponse<List<BackdropAssetDto>> listAssets() {
        return ApiResponse.success(backdropAssetService.listAssets(currentUserContext.requireCurrentUserId()));
    }

    /**
     * 上传背景素材。
     *
     * @param file 素材文件
     * @return 新建素材 DTO
     */
    @Operation(summary = "上传背景素材", description = "单文件上传,服务端同步完成校验、扫描、落库与缩略图")
    @PreAuthorize("hasAuthority('" + Permissions.BACKDROP_WRITE + "')")
    @PostMapping(value = "/api/v1/backdrops", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ApiResponse<BackdropAssetDto> uploadAsset(
            @Parameter(description = "背景素材文件") @RequestParam("file") MultipartFile file) {
        return ApiResponse.success(
                backdropAssetService.uploadAsset(currentUserContext.requireCurrentUserId(), file));
    }

    /**
     * 删除背景素材。
     *
     * @param assetId 素材 ID
     * @return 空响应
     */
    @Operation(summary = "删除背景素材", description = "统一 404 防资源枚举;删除后引用由客户端归一化处理")
    @PreAuthorize("hasAuthority('" + Permissions.BACKDROP_WRITE + "')")
    @DeleteMapping("/api/v1/backdrops/{assetId}")
    public ApiResponse<Void> deleteAsset(
            @Parameter(description = "素材 ID") @PathVariable UUID assetId) {
        backdropAssetService.deleteAsset(currentUserContext.requireCurrentUserId(), assetId);
        return ApiResponse.success(null);
    }
}
