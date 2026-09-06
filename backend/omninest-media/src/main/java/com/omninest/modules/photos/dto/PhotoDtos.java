package com.omninest.modules.photos.dto;

import com.omninest.modules.photos.domain.PhotoItem;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * 照片模块的数据传输对象集合。
 *
 * @author OmniNest
 */
public final class PhotoDtos {

    public record PhotoItemDto(
            UUID id,
            UUID fileNodeId,
            String title,
            String description,
            Integer width,
            Integer height,
            Integer orientation,
            Instant dateTaken,
            String cameraMake,
            String cameraModel,
            String aperture,
            String shutterSpeed,
            Integer iso,
            String focalLength,
            String flash,
            String whiteBalance,
            String meteringMode,
            String lensModel,
            Double gpsLatitude,
            Double gpsLongitude,
            Map<String, Object> gpsLocation,
            String format,
            long fileSize,
            String coverUrl,
            String sourceUrl,
            String metadataStatus,
            boolean favorite,
            Instant createdAt,
            List<String> tags,
            Map<String, Object> providerMetadata,
            PhotoContentAnalysisDto contentAnalysis
    ) {
        /**
         * 从 PhotoItem 实体和已解析的关联数据创建 DTO。
         * 避免在多个 Service 中重复映射逻辑。
         */
        public static PhotoItemDto fromEntity(
                PhotoItem photo,
                String coverUrl,
                boolean favorite,
                List<String> tags
        ) {
            return fromEntity(photo, coverUrl, favorite, tags, null, null);
        }

        /**
         * 从照片实体和内容分析结果创建详情 DTO。
         */
        public static PhotoItemDto fromEntity(
                PhotoItem photo,
                String coverUrl,
                boolean favorite,
                List<String> tags,
                PhotoContentAnalysisDto contentAnalysis
        ) {
            return fromEntity(photo, coverUrl, favorite, tags, null, contentAnalysis);
        }

        /**
         * 从照片实体和详情资源地址创建 DTO。
         * 原图地址只在详情接口生成，避免列表和仪表盘批量签发大文件地址。
         */
        public static PhotoItemDto fromEntity(
                PhotoItem photo,
                String coverUrl,
                boolean favorite,
                List<String> tags,
                String sourceUrl,
                PhotoContentAnalysisDto contentAnalysis
        ) {
            return new PhotoItemDto(
                    photo.getId(),
                    photo.getFileNodeId(),
                    photo.getTitle(),
                    photo.getDescription(),
                    photo.getWidth(),
                    photo.getHeight(),
                    photo.getOrientation(),
                    photo.getDateTaken(),
                    photo.getCameraMake(),
                    photo.getCameraModel(),
                    photo.getAperture(),
                    photo.getShutterSpeed(),
                    photo.getIso(),
                    photo.getFocalLength(),
                    photo.getFlash(),
                    photo.getWhiteBalance(),
                    photo.getMeteringMode(),
                    photo.getLensModel(),
                    photo.getGpsLatitude() != null
                            ? photo.getGpsLatitude().doubleValue()
                            : null,
                    photo.getGpsLongitude() != null
                            ? photo.getGpsLongitude().doubleValue()
                            : null,
                    photo.getGpsLocation(),
                    photo.getFormat(),
                    photo.getFileSize(),
                    coverUrl,
                    sourceUrl,
                    photo.getMetadataStatus(),
                    favorite,
                    photo.getCreatedAt(),
                    tags,
                    photo.getProviderMetadata(),
                    contentAnalysis
            );
        }
    }

    /**
     * 照片内容分析结果。
     *
     * @param status 分析状态
     * @param pipelineVersion 分析流水线版本
     * @param completedAt 完成时间
     * @param labels 结构化自动标签
     */
    public record PhotoContentAnalysisDto(
            String status,
            String pipelineVersion,
            Instant completedAt,
            List<PhotoContentLabelDto> labels
    ) {
    }

    /**
     * 照片内容分析标签。
     *
     * @param id 标签标识
     * @param namespace 命名空间
     * @param code 稳定标签编码
     * @param confidence 置信度
     * @param source 结果来源
     * @param state 标签状态
     * @param boxes 归一化边界框
     */
    public record PhotoContentLabelDto(
            UUID id,
            String namespace,
            String code,
            float confidence,
            String source,
            String state,
            List<Map<String, Object>> boxes
    ) {
    }

    /**
     * 照片网格分页使用的轻量列表条目。
     *
     * @author OmniNest
     */
    public record PhotoListItemDto(
            UUID id,
            UUID fileNodeId,
            String title,
            String description,
            Integer width,
            Integer height,
            Integer orientation,
            Instant dateTaken,
            Double gpsLatitude,
            Double gpsLongitude,
            Map<String, Object> gpsLocation,
            String format,
            long fileSize,
            String coverUrl,
            String sourceUrl,
            String metadataStatus,
            boolean favorite,
            Instant createdAt,
            List<String> tags
    ) {}

    public record PhotoDashboardDto(
            long totalPhotos,
            long totalAlbums,
            long totalFavorites,
            long trashCount,
            List<PhotoItemDto> recentPhotos,
            List<PhotoItemDto> favoritePhotos
    ) {}

    /** 回收站批量操作逐项结果。 */
    public record PhotoTrashResultDto(
            UUID photoId,
            boolean success,
            String message
    ) {}

    public record PhotoAlbumDto(
            UUID id,
            String name,
            String description,
            String coverUrl,
            int photoCount,
            Instant createdAt,
            Instant updatedAt
    ) {}

    public record PhotoAlbumDetailDto(
            PhotoAlbumDto album,
            List<PhotoItemDto> photos
    ) {}

    public record CreateAlbumRequest(
            @NotBlank
            @Size(max = 200) String name,
            @Size(max = 2000) String description
    ) {}

    public record AddPhotosToAlbumRequest(
            @NotEmpty
            @Size(max = 1000) List<@NotNull UUID> photoIds
    ) {}

    public record PhotoScanJobDto(
            UUID id,
            String status,
            int scannedFiles,
            String message,
            Instant createdAt,
            Instant updatedAt
    ) {}

    // ─── 时间线 DTO ───

    public record PhotoTimelineDto(
            List<PhotoYearGroup> years
    ) {}

    public record PhotoYearGroup(
            int year,
            List<PhotoMonthGroup> months
    ) {}

    public record PhotoMonthGroup(
            int month,
            int photoCount,
            List<PhotoItemDto> previewPhotos
    ) {}

    /**
     * 时间线月份分页条目。
     *
     * @author OmniNest
     */
    public record PhotoTimelineMonthDto(
            int year,
            int month,
            int photoCount,
            List<PhotoListItemDto> previewPhotos
    ) {}

    // ─── 分组 DTO ───

    public record PhotoGroupDto(
            String groupKey,
            int photoCount,
            List<PhotoItemDto> photos
    ) {}

    // ─── 标签 DTO ───

    public record AddTagRequest(
            @NotBlank
            @Size(max = 100) String tag
    ) {}

    // ─── 批量任务 DTO ───

    public record PhotoBatchTaskDto(
            UUID id,
            String taskType,
            String status,
            int totalItems,
            int processedItems,
            String result,
            String errorMessage,
            Instant createdAt
    ) {}

    public record CreateBatchTaskRequest(
            @NotBlank
            @Pattern(regexp = "TAG|MOVE|UPDATE_DATE|DOWNLOAD") String taskType,
            @NotEmpty
            @Size(max = 1000) List<@NotNull UUID> photoIds,
            @Size(max = 20) Map<String, Object> params
    ) {}

    /**
     * 批量永久删除照片请求。
     *
     * @param photoIds 照片 ID 列表
     * @author OmniNest
     */
    public record DeletePhotosRequest(
            @NotEmpty
            @Size(max = 200) List<@NotNull UUID> photoIds
    ) {}

    /**
     * 照片批量 ZIP 的短期下载票据。
     *
     * @author OmniNest
     */
    public record PhotoBatchDownloadTicketDto(
            String url,
            String fileName,
            long sizeBytes,
            Instant expiresAt,
            String sha256
    ) {}

    // ─── 编辑版本 DTO ───

    public record PhotoEditVersionDto(
            UUID id,
            int versionNumber,
            String editType,
            Map<String, Object> editParams,
            Instant createdAt
    ) {}

    public record EditRequest(
            @NotBlank String editType,
            Map<String, Object> editParams
    ) {}

    // ─── 分享 DTO ───

    public record PhotoShareLinkDto(
            UUID id,
            String token,
            String resourceType,
            UUID resourceId,
            Instant expiresAt,
            Integer maxAccessCount,
            int accessCount,
            Instant createdAt
    ) {}

    public record CreateAlbumShareRequest(
            String password,
            Instant expiresAt,
            Integer maxAccessCount
    ) {}

    public record PhotoSharedAlbumDto(
            String albumName,
            String description,
            List<PhotoItemDto> photos,
            int page,
            int size,
            long total
    ) {}

    // ─── AI 人脸聚类 DTO ───

    public record PhotoFaceClusterDto(
            UUID id,
            String name,
            int faceCount,
            String coverPhotoUrl
    ) {}

    public record NameClusterRequest(
            @NotBlank
            @Size(max = 200) String name
    ) {}

    /**
     * 照片图像分析异步任务提交结果。
     *
     * @param taskId 通用任务标识
     * @param status 初始任务状态
     * @param totalItems 预计处理照片数
     * @author OmniNest
     */
    public record PhotoAiTaskDto(
            UUID taskId,
            String status,
            long totalItems
    ) {}

    // ─── 备份状态 DTO ───

    public record PhotoBackupStatusDto(
            String deviceId,
            Instant lastBackupAt,
            int lastPhotoCount
    ) {}

    public record BackupStatusRequest(
            @NotBlank
            @Size(max = 200) String deviceId
    ) {}

    public record BackupReportRequest(
            String deviceId,
            int photoCount
    ) {}

    public record CheckDuplicateRequest(
            List<String> contentHashes
    ) {}

    public record PhotoRelationEdgeDto(
            String sourceType,
            String sourceKey,
            String targetType,
            String targetKey,
            long weight
    ) {
    }

    public record PhotoRelationNodeDto(
            String type,
            String key,
            String label,
            long weight
    ) {
    }

    public record PhotoRelationsDto(
            List<PhotoRelationNodeDto> nodes,
            List<PhotoRelationEdgeDto> edges,
            boolean truncated
    ) {
    }
}