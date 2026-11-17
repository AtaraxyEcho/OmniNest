package com.omninest.modules.video.dto;

import com.omninest.modules.video.domain.MediaImportPolicy;
import com.omninest.modules.video.domain.MediaLibraryType;
import com.omninest.modules.video.domain.MediaLibraryVisibility;
import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * 影视库来源接口数据结构。
 *
 * @author OmniNest
 */
public final class VideoLibrarySourceDtos {

    private VideoLibrarySourceDtos() {
    }

    /**
     * 挂载媒体库一键开通/更新请求。
     *
     * <p>系统在挂载根下按约定目录 Movie、TV、Anime 维护三个类型库源，
     * 管理员只需开关启用与扫描后自动入库，无需手动划分媒体库类型。</p>
     *
     * @param mountKey 部署可信挂载键
     * @param enabled 是否启用该挂载的媒体库
     * @param autoImport 扫描后是否自动入库已匹配候选
     */
    @Schema(description = "挂载媒体库开通请求")
    public record MountLibraryProvisionRequest(
            @NotBlank @Size(max = 80) String mountKey,
            boolean enabled,
            boolean autoImport
    ) {
    }

    /**
     * 挂载媒体库开通结果。
     *
     * @param mountKey 挂载键
     * @param storageLocationId 挂载根存储位置 ID
     * @param enabled 是否启用
     * @param autoImport 是否自动入库
     * @param sources 约定目录下的三个类型库源
     */
    @Schema(description = "挂载媒体库开通结果")
    public record MountLibraryProvisionDto(
            String mountKey,
            UUID storageLocationId,
            boolean enabled,
            boolean autoImport,
            List<VideoLibrarySourceDto> sources
    ) {
    }

    /**
     * 创建影视库来源请求。
     *
     * @param name 显示名称
     * @param storageLocationId 存储位置 ID，与 mountKey 二选一
     * @param mountKey 部署可信挂载键，与 storageLocationId 二选一；提供时由服务端
     *                 查找或创建挂载根的系统级存储位置，调用者需额外持有系统配置管理权限
     * @param relativeRoot 存储位置内相对目录
     * @param libraryType 媒体库类型
     * @param enabled 是否启用
     */
    @Schema(description = "创建影视库来源请求")
    public record CreateVideoLibrarySourceRequest(
            @NotBlank @Size(max = 160) String name,
            @Size(max = 80) String mountKey,
            UUID storageLocationId,
            @Size(max = 2048) String relativeRoot,
            MediaLibraryType libraryType,
            MediaImportPolicy importPolicy,
            boolean enabled
    ) {
    }

    /**
     * 更新影视库来源请求。
     *
     * @param name 显示名称
     * @param relativeRoot 存储位置内相对目录
     * @param libraryType 媒体库类型
     * @param enabled 是否启用
     */
    @Schema(description = "更新影视库来源请求")
    public record UpdateVideoLibrarySourceRequest(
            @NotBlank @Size(max = 160) String name,
            @Size(max = 2048) String relativeRoot,
            MediaLibraryType libraryType,
            MediaImportPolicy importPolicy,
            boolean enabled
    ) {
    }

    /**
     * 影视库来源响应。
     *
     * @param id 来源 ID
     * @param name 显示名称
     * @param storageLocationId 存储位置 ID
     * @param relativeRoot 相对目录
     * @param libraryType 媒体库类型
     * @param enabled 是否启用
     * @param scanStatus 扫描状态
     * @param lastScannedAt 上次扫描时间
     * @param lastErrorCode 上次错误码
     * @param lastScannedCount 上次发现视频数
     * @param lastCreatedCount 上次新建引用数
     * @param createdAt 创建时间
     * @param updatedAt 更新时间
     */
    @Schema(description = "影视库来源")
    public record VideoLibrarySourceDto(
            UUID id,
            String name,
            UUID storageLocationId,
            String relativeRoot,
            MediaLibraryType libraryType,
            MediaImportPolicy importPolicy,
            MediaLibraryVisibility visibilityType,
            boolean enabled,
            String scanStatus,
            String healthStatus,
            Instant lastScannedAt,
            Instant lastSuccessfulScanAt,
            String lastErrorCode,
            int lastScannedCount,
            int lastCreatedCount,
            int lastCandidateCount,
            int lastMissingCount,
            Instant createdAt,
            Instant updatedAt,
            long version
    ) {
    }
}
