package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.util.LikePatterns;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.repository.FileNodeRepository;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

/**
 * 文件节点读取与父级校验的共享支持。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
class FileNodeLookupSupport {

    private final FileNodeRepository fileNodeRepository;

    FileNode findActiveNode(UUID ownerUserId, UUID fileId) {
        return fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(fileId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
    }

    FileNode resolveParent(UUID ownerUserId, UUID parentId) {
        if (parentId == null) {
            return null;
        }
        FileNode parent = fileNodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(parentId, ownerUserId)
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "父级文件夹不存在"));
        if (!NodeType.FOLDER.getValue().equals(parent.getNodeType())) {
            throw new BusinessException(ErrorCode.FILE_PATH_INVALID, "父级节点不是文件夹");
        }
        return parent;
    }

    String subtreePrefix(FileNode node) {
        return subtreePrefix(node.getNormalizedPath());
    }

    String subtreePrefix(String path) {
        return LikePatterns.escapeSpecials(path + "/");
    }
}
