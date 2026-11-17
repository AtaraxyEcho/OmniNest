package com.omninest.modules.file.dto;

import io.swagger.v3.oas.annotations.media.Schema;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.UUID;

/**
 * 存储位置接口数据结构。
 *
 * @author OmniNest
 */
public final class StorageLocationDtos {

    private StorageLocationDtos() {
    }

    /**
     * 创建存储位置请求。
     *
     * @param name 显示名称
     * @param mountKey 部署挂载键
     * @param relativeRoot 挂载点内相对根目录
     * @param scopeType 作用域类型
     * @param scopeId 作用域 ID
     * @param enabled 是否启用
     */
    @Schema(description = "创建本地只读存储位置请求")
    public record CreateStorageLocationRequest(
            @NotBlank @Size(max = 160) String name,
            @NotBlank @Size(max = 80) String mountKey,
            @Size(max = 2048) String relativeRoot,
            @NotBlank @Size(max = 24) String scopeType,
            UUID scopeId,
            boolean enabled
    ) {
    }

    /**
     * 更新存储位置请求。
     *
     * @param name 显示名称
     * @param enabled 是否启用
     */
    @Schema(description = "更新本地只读存储位置请求")
    public record UpdateStorageLocationRequest(
            @NotBlank @Size(max = 160) String name,
            boolean enabled
    ) {
    }

    /**
     * 存储位置响应。
     *
     * @param id 存储位置 ID
     * @param name 显示名称
     * @param providerType 提供者类型
     * @param managementMode 管理模式
     * @param mountKey 部署挂载键
     * @param relativeRoot 相对根目录
     * @param scopeType 作用域类型
     * @param scopeId 作用域 ID
     * @param enabled 是否启用
     * @param healthStatus 健康状态
     * @param nodeId 当前节点 ID
     * @param createdAt 创建时间
     * @param updatedAt 更新时间
     */
    @Schema(description = "本地只读存储位置")
    public record StorageLocationDto(
            UUID id,
            String name,
            String providerType,
            String managementMode,
            String mountKey,
            String relativeRoot,
            String scopeType,
            UUID scopeId,
            boolean enabled,
            String healthStatus,
            String nodeId,
            Instant createdAt,
            Instant updatedAt
    ) {
    }

    /**
     * 跨模块使用的存储位置描述符。
     *
     * @param id 存储位置 ID
     * @param name 显示名称
     * @param providerType 提供者类型
     * @param mountKey 挂载键
     * @param relativeRoot 相对根目录
     * @param scopeType 作用域类型
     * @param scopeId 作用域 ID
     * @param enabled 是否启用
     * @param healthStatus 健康状态
     * @param rootName 根目录显示名称，不包含宿主机路径
     */
    public record StorageLocationDescriptor(
            UUID id,
            String name,
            String providerType,
            String mountKey,
            String relativeRoot,
            String scopeType,
            UUID scopeId,
            boolean enabled,
            String healthStatus,
            String rootName
    ) {
    }

    /**
     * 安全目录树节点。
     *
     * @param nodeId 服务端稳定节点标识
     * @param name 目录名称
     * @param relativePath 存储位置内安全相对路径
     * @param hasChildren 是否存在可展开子目录
     */
    public record StorageDirectoryDto(
            String nodeId,
            String name,
            String relativePath,
            boolean hasChildren
    ) {
    }

    /** 不暴露物理路径的部署可信挂载描述。 */
    public record TrustedMountDto(
            String mountKey,
            String displayName,
            boolean available
    ) {
    }
}
