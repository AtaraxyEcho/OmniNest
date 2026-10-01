package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import java.time.Instant;
import java.util.UUID;

@Schema(description = "文件节点信息")
public record FileNodeDto(
        @Schema(description = "文件节点 ID") UUID id,
        @Schema(description = "父文件夹 ID") UUID parentId,
        @Schema(description = "节点类型", example = "FILE", allowableValues = {"FILE", "FOLDER"}) String nodeType,
        @Schema(description = "文件名", example = "文档.pdf") String name,
        @Schema(description = "规范化路径", example = "/documents/文档.pdf") String normalizedPath,
        @Schema(description = "MIME 类型", example = "application/pdf") String mimeType,
        @Schema(description = "文件大小（字节）", example = "1048576") long sizeBytes,
        @Schema(description = "是否已分享", example = "false") boolean shared,
        @Schema(description = "分享时间") Instant sharedAt,
        @Schema(description = "更新时间") Instant updatedAt,
        @Schema(description = "空间类型", example = "PERSONAL", allowableValues = {"PERSONAL", "SHARED"}) String spaceType,
        @Schema(description = "上传者用户 ID（仅共享空间文件）") UUID uploadedBy,
        @Schema(description = "上传者显示名；个人空间即所有者，共享空间为实际上传者") String uploadedByName,
        @Schema(description = "媒体封面文件 ID（音乐/影视/阅读库反查，无封面为空）") UUID coverFileId,
        @Schema(description = "上传后媒体自动导入任务 ID") UUID mediaAutoImportTaskId
) {

    /**
     * 保留既有文件节点构造调用，普通文件查询没有媒体自动导入任务。
     */
    public FileNodeDto(
            UUID id,
            UUID parentId,
            String nodeType,
            String name,
            String normalizedPath,
            String mimeType,
            long sizeBytes,
            boolean shared,
            Instant sharedAt,
            Instant updatedAt,
            String spaceType,
            UUID uploadedBy
    ) {
        this(id, parentId, nodeType, name, normalizedPath, mimeType, sizeBytes, shared,
                sharedAt, updatedAt, spaceType, uploadedBy, null, null);
    }

    /**
     * 带上传者显示名的完整构造，供查询服务批量解析后填充。
     */
    public FileNodeDto(
            UUID id,
            UUID parentId,
            String nodeType,
            String name,
            String normalizedPath,
            String mimeType,
            long sizeBytes,
            boolean shared,
            Instant sharedAt,
            Instant updatedAt,
            String spaceType,
            UUID uploadedBy,
            String uploadedByName
    ) {
        this(id, parentId, nodeType, name, normalizedPath, mimeType, sizeBytes, shared,
                sharedAt, updatedAt, spaceType, uploadedBy, uploadedByName, null, null);
    }

    /**
     * 带上传者显示名与媒体封面的完整构造，供查询服务批量解析后填充。
     */
    public FileNodeDto(
            UUID id,
            UUID parentId,
            String nodeType,
            String name,
            String normalizedPath,
            String mimeType,
            long sizeBytes,
            boolean shared,
            Instant sharedAt,
            Instant updatedAt,
            String spaceType,
            UUID uploadedBy,
            String uploadedByName,
            UUID coverFileId
    ) {
        this(id, parentId, nodeType, name, normalizedPath, mimeType, sizeBytes, shared,
                sharedAt, updatedAt, spaceType, uploadedBy, uploadedByName, coverFileId, null);
    }
}
