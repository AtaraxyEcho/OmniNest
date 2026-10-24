package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.FileFavorite;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileNodeDto;
import com.omninest.modules.file.repository.FileFavoriteRepository;
import com.omninest.modules.file.repository.FileNodeRepository;
import java.util.LinkedHashMap;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.stream.Collectors;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文件收藏服务。
 * 负责收藏列表查询与单个、批量收藏维护。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileFavoriteService {
    private final FileFavoriteRepository favoriteRepository;
    private final FileNodeRepository fileNodeRepository;
    private final FileNodeSupport fileNodeSupport;
    private final FileSyncEventWriter syncEventWriter;
    private final SharedSpaceService sharedSpaceService;

    /**
     * 分页查询当前用户收藏的文件。
     *
     * @param ownerUserId 用户 ID
     * @param page        页码（从 0 开始）
     * @param size        每页条数
     * @return 收藏文件分页
     */
    @Transactional(readOnly = true)
    public Page<FileNodeDto> listFavoriteFilesPage(UUID ownerUserId, int page, int size) {
        Pageable pageable = FilePageRequests.of(page, size);
        Page<UUID> favoriteNodeIds = favoriteRepository.findFavoriteNodeIds(ownerUserId, pageable);
        if (favoriteNodeIds.isEmpty()) {
            return new PageImpl<>(List.of(), pageable, favoriteNodeIds.getTotalElements());
        }
        Map<UUID, FileNode> nodesById = fileNodeRepository.findAllById(favoriteNodeIds.getContent())
                .stream()
                .filter(node -> !node.isDeleted())
                .collect(Collectors.toMap(FileNode::getId, node -> node, (left, right) -> left, LinkedHashMap::new));
        List<FileNode> nodes = favoriteNodeIds.getContent()
                .stream()
                .map(nodesById::get)
                .filter(Objects::nonNull)
                .toList();
        List<FileNodeDto> items = fileNodeSupport.toNodeDtos(nodes);
        return new PageImpl<>(items, pageable, favoriteNodeIds.getTotalElements());
    }

    /**
     * 添加收藏。
     *
     * @param ownerUserId 用户 ID
     * @param fileId      文件节点 ID
     * @return 收藏的文件节点
     */
    @Transactional(rollbackFor = Exception.class)
    public FileNodeDto addFavorite(UUID ownerUserId, UUID fileId) {
        FileNode node = fileNodeSupport.findVisibleNode(ownerUserId, fileId);
        boolean created = !favoriteRepository.existsByOwnerUserIdAndFileNode_Id(ownerUserId, fileId);
        if (created) {
            FileFavorite favorite = new FileFavorite();
            favorite.setOwnerUserId(ownerUserId);
            favorite.setFileNode(node);
            favoriteRepository.save(favorite);
            syncEventWriter.recordFileEvent(ownerUserId, fileId, Map.of("favorite", true));
        }
        return fileNodeSupport.toNodeDto(node);
    }

    /**
     * 取消收藏。
     *
     * @param ownerUserId 用户 ID
     * @param fileId      文件节点 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void removeFavorite(UUID ownerUserId, UUID fileId) {
        favoriteRepository.findByOwnerUserIdAndFileNode_Id(ownerUserId, fileId)
                .ifPresent(favorite -> {
                    favoriteRepository.delete(favorite);
                    syncEventWriter.recordFileEvent(ownerUserId, fileId, Map.of("favorite", false));
                });
    }

    /**
     * 批量添加收藏（幂等，已收藏的跳过）。
     *
     * @param ownerUserId 用户 ID
     * @param fileIds     文件节点 ID 列表
     * @return 实际加入收藏的文件节点列表
     */
    @Transactional(rollbackFor = Exception.class)
    public List<FileNodeDto> batchAddFavorites(UUID ownerUserId, List<UUID> fileIds) {
        // 与单文件收藏同口径：自己的节点直接可见，他人节点只有共享空间且具备浏览权限时可见。
        List<FileNode> candidates = fileNodeRepository.findAllById(fileIds).stream()
                .filter(node -> !node.isDeleted())
                .toList();
        boolean sharedSpaceVisible = candidates.stream()
                .anyMatch(node -> !Objects.equals(node.getOwnerUserId(), ownerUserId))
                && sharedSpaceService.canBrowse(ownerUserId);
        List<FileNode> nodes = candidates.stream()
                .filter(node -> Objects.equals(node.getOwnerUserId(), ownerUserId)
                        || (sharedSpaceVisible && node.getSpaceType() == SpaceType.SHARED))
                .toList();
        if (nodes.isEmpty()) {
            return List.of();
        }
        Set<UUID> existing = new HashSet<>(favoriteRepository.findFavoritedNodeIds(
                ownerUserId, nodes.stream().map(FileNode::getId).toList()));
        List<FileFavorite> created = new ArrayList<>();
        for (FileNode node : nodes) {
            if (existing.add(node.getId())) {
                FileFavorite favorite = new FileFavorite();
                favorite.setOwnerUserId(ownerUserId);
                favorite.setFileNode(node);
                created.add(favorite);
            }
        }
        if (!created.isEmpty()) {
            favoriteRepository.saveAll(created);
            syncEventWriter.recordFileLibraryInvalidation(ownerUserId, created.size());
        }
        return fileNodeSupport.toNodeDtos(nodes);
    }

    /**
     * 批量取消收藏。
     *
     * @param ownerUserId 用户 ID
     * @param fileIds     文件节点 ID 列表
     */
    @Transactional(rollbackFor = Exception.class)
    public void batchRemoveFavorites(UUID ownerUserId, List<UUID> fileIds) {
        favoriteRepository.deleteByOwnerUserIdAndFileNode_IdIn(ownerUserId, fileIds);
        if (!fileIds.isEmpty()) {
            syncEventWriter.recordFileLibraryInvalidation(ownerUserId, fileIds.size());
        }
    }
}
