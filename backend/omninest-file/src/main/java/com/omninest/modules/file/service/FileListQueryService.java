package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileTypeCategories;
import com.omninest.modules.file.domain.SourceType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileNodeDto;
import com.omninest.modules.file.repository.FileNodeRepository;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文件列表、分类与回收站只读查询。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
class FileListQueryService {

    private final FileNodeRepository fileNodeRepository;
    private final FileNodeLookupSupport lookup;
    private final FileNodeDtoAssembler assembler;

    @Transactional(readOnly = true)
    public List<FileNodeDto> listFiles(UUID ownerUserId, UUID parentId) {
        return listFiles(ownerUserId, parentId, null);
    }

    @Transactional(readOnly = true)
    public List<FileNodeDto> listFiles(UUID ownerUserId, UUID parentId, String category) {
        String normalizedCategory = normalizeCategory(category);
        List<FileNode> nodes = listNodesForView(ownerUserId, parentId, normalizedCategory);
        List<FileNode> sorted = nodes.stream()
                .filter(node -> matchesCategory(node, normalizedCategory))
                .sorted(Comparator.comparing(FileNode::getNodeType).reversed()
                        .thenComparing(FileNode::getName, String.CASE_INSENSITIVE_ORDER))
                .toList();
        Map<UUID, String> uploaderNames = assembler.resolveUploaderNames(sorted);
        Map<UUID, UUID> coverMap = assembler.resolveAliveCovers(sorted);
        return sorted.stream()
                .map(node -> assembler.toDto(node, uploaderNames, coverMap.get(node.getId())))
                .toList();
    }

    @Transactional(readOnly = true)
    public Page<FileNodeDto> listFilesPage(
            UUID ownerUserId,
            UUID parentId,
            String category,
            int page,
            int size) {
        String normalizedCategory = normalizeCategory(category);
        Pageable pageable = filePageable(page, size);
        Page<FileNode> nodes;
        if (normalizedCategory == null) {
            nodes = parentId == null
                    ? fileNodeRepository.findVisiblePersonalRoot(ownerUserId, SpaceType.PERSONAL, pageable)
                    : fileNodeRepository.findVisiblePersonalChildren(ownerUserId, parentId, pageable);
        } else if (parentId == null) {
            nodes = fileNodeRepository.findVisiblePersonalCategoryPage(
                    ownerUserId, SpaceType.PERSONAL, normalizedCategory, pageable);
        } else {
            nodes = fileNodeRepository.findVisibleSubtreeCategoryPage(
                    ownerUserId,
                    resolveSubtreePrefix(ownerUserId, parentId),
                    normalizedCategory,
                    pageable);
        }
        Map<UUID, String> uploaderNames = assembler.resolveUploaderNames(nodes.getContent());
        Map<UUID, UUID> covers = assembler.resolveAliveCovers(nodes.getContent());
        return nodes.map(node -> assembler.toDto(node, uploaderNames, covers.get(node.getId())));
    }

    @Transactional(readOnly = true)
    public Page<FileNodeDto> listRecycleBinPage(UUID ownerUserId, SpaceType spaceType, int page, int size) {
        Pageable pageable = FilePageRequests.of(
                page,
                size,
                Sort.by(Sort.Order.desc("deletedAt"), Sort.Order.desc("id")));
        Page<FileNode> nodes = spaceType == SpaceType.SHARED
                ? fileNodeRepository.findSharedRecyclePage(ownerUserId, spaceType, pageable)
                : fileNodeRepository.findPersonalRecyclePage(ownerUserId, spaceType, pageable);
        Map<UUID, String> uploaderNames = assembler.resolveUploaderNames(nodes.getContent());
        Map<UUID, UUID> covers = assembler.resolveAliveCovers(nodes.getContent());
        return nodes.map(node -> assembler.toDto(node, uploaderNames, covers.get(node.getId())));
    }

    private String resolveSubtreePrefix(UUID ownerUserId, UUID parentId) {
        FileNode parent = lookup.resolveParent(ownerUserId, parentId);
        return lookup.subtreePrefix(parent.getNormalizedPath());
    }

    private String normalizeCategory(String category) {
        if (category == null || category.isBlank() || "all".equalsIgnoreCase(category)) {
            return null;
        }
        String normalizedCategory = category.trim().toLowerCase(Locale.ROOT);
        Set<String> allowedCategories = Set.of(
                "image",
                "video",
                "audio",
                "document",
                "novel",
                "comic",
                "archive",
                "other"
        );
        if (!allowedCategories.contains(normalizedCategory)) {
            throw new BusinessException(ErrorCode.PARAM_ERROR, "文件分类不支持");
        }
        return normalizedCategory;
    }

    private Pageable filePageable(int page, int size) {
        int safePage = Math.max(page, 0);
        int safeSize = Math.min(Math.max(size, 1), 200);
        Sort sort = Sort.by(
                Sort.Order.desc("nodeType"),
                Sort.Order.asc("name").ignoreCase());
        return PageRequest.of(safePage, safeSize, sort);
    }

    private List<FileNode> listNodesForView(UUID ownerUserId, UUID parentId, String category) {
        if (category == null) {
            List<FileNode> nodes = parentId == null
                    ? fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndParentIdIsNullAndDeletedFalse(
                            ownerUserId, SpaceType.PERSONAL)
                    : fileNodeRepository.findByOwnerUserIdAndParentIdAndDeletedFalse(ownerUserId, parentId);
            return visibleNodes(nodes);
        }
        if (parentId == null) {
            return visibleNodes(fileNodeRepository.findByOwnerUserIdAndSpaceTypeAndDeletedFalse(
                    ownerUserId, SpaceType.PERSONAL));
        }
        FileNode parent = lookup.resolveParent(ownerUserId, parentId);
        return visibleNodes(fileNodeRepository
                .findByOwnerUserIdAndSpaceTypeAndNormalizedPathStartingWithAndDeletedFalse(
                        ownerUserId,
                        SpaceType.PERSONAL,
                        lookup.subtreePrefix(parent)
                ));
    }

    private List<FileNode> visibleNodes(List<FileNode> nodes) {
        return nodes.stream()
                .filter(node -> !"DERIVED".equals(node.getSourceType()))
                .filter(node -> !SourceType.LOCAL_FILESYSTEM.getValue().equals(node.getSourceType()))
                .toList();
    }

    private boolean matchesCategory(FileNode node, String category) {
        if (category == null) {
            return true;
        }
        return category.equals(FileTypeCategories.resolve(
                node.getName(), node.getMimeType(), node.getNodeType()));
    }
}
