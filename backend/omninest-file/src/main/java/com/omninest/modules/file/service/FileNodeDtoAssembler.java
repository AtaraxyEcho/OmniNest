package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileTypeCategories;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.dto.FileNodeDto;
import com.omninest.modules.file.port.MediaCoverDirectory;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.user.port.UserNameDirectory;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 文件节点 DTO 装配：批量补齐上传者显示名与存活媒体封面。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
class FileNodeDtoAssembler {

    private final FileNodeRepository fileNodeRepository;
    private final UserNameDirectory userNameDirectory;
    private final MediaCoverDirectory mediaCoverDirectory;

    FileNodeDto toDto(FileNode node) {
        Map<UUID, UUID> covers = resolveAliveCovers(List.of(node));
        return toDto(node, resolveUploaderNames(List.of(node)), covers.get(node.getId()));
    }

    /**
     * 上传者显示名：共享空间取实际上传者，其余取所有者；
     * 未知用户不填充，由前端按缺省呈现。
     */
    FileNodeDto toDto(FileNode node, Map<UUID, String> uploaderNames, UUID coverFileId) {
        UUID uploaderId = node.getUploadedBy() != null ? node.getUploadedBy() : node.getOwnerUserId();
        return new FileNodeDto(
                node.getId(),
                node.getParentId(),
                node.getNodeType(),
                node.getName(),
                node.getNormalizedPath(),
                node.getMimeType(),
                node.getSizeBytes(),
                node.isShared(),
                node.getSharedAt(),
                node.getUpdatedAt(),
                node.getSpaceType() != null ? node.getSpaceType().getValue() : "PERSONAL",
                node.getUploadedBy(),
                uploaderNames.get(uploaderId),
                coverFileId
        );
    }

    /**
     * 批量解析本组节点的存活媒体封面（媒体类 FILE 节点才发起反查）。
     */
    Map<UUID, UUID> resolveAliveCovers(List<FileNode> nodes) {
        Map<UUID, Set<UUID>> mediaIdsByOwner = new HashMap<>();
        for (FileNode node : nodes) {
            if (!NodeType.FILE.getValue().equals(node.getNodeType())) {
                continue;
            }
            String category = FileTypeCategories.resolve(
                    node.getName(), node.getMimeType(), node.getNodeType());
            boolean mediaCategory = FileTypeCategories.VIDEO.equals(category)
                    || FileTypeCategories.AUDIO.equals(category)
                    || FileTypeCategories.NOVEL.equals(category)
                    || FileTypeCategories.COMIC.equals(category);
            if (!mediaCategory) {
                continue;
            }
            mediaIdsByOwner
                    .computeIfAbsent(node.getOwnerUserId(), key -> new HashSet<>())
                    .add(node.getId());
        }
        if (mediaIdsByOwner.isEmpty()) {
            return Map.of();
        }
        Map<UUID, UUID> covers = new HashMap<>();
        mediaIdsByOwner.forEach((ownerUserId, mediaFileIds) ->
                covers.putAll(mediaCoverDirectory.resolveCoverFileIds(ownerUserId, mediaFileIds)));
        if (covers.isEmpty()) {
            return Map.of();
        }
        Set<UUID> aliveIds = new HashSet<>();
        for (FileNode coverNode : fileNodeRepository.findAllById(covers.values())) {
            if (!coverNode.isDeleted() && NodeType.FILE.getValue().equals(coverNode.getNodeType())) {
                aliveIds.add(coverNode.getId());
            }
        }
        Map<UUID, UUID> alive = new HashMap<>();
        for (Map.Entry<UUID, UUID> entry : covers.entrySet()) {
            if (aliveIds.contains(entry.getValue())) {
                alive.put(entry.getKey(), entry.getValue());
            }
        }
        return alive;
    }

    /**
     * 批量解析一批节点的上传者显示名，供列表接口一次查询填充。
     */
    Map<UUID, String> resolveUploaderNames(List<FileNode> nodes) {
        Set<UUID> uploaderIds = new HashSet<>();
        for (FileNode node : nodes) {
            UUID uploaderId = node.getUploadedBy() != null ? node.getUploadedBy() : node.getOwnerUserId();
            if (uploaderId != null) {
                uploaderIds.add(uploaderId);
            }
        }
        return userNameDirectory.resolveDisplayNames(uploaderIds);
    }
}
