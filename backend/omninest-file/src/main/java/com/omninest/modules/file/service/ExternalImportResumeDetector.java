package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SourceType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.domain.StorageImportTask;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import java.nio.file.Path;
import java.util.Optional;
import java.util.UUID;

/**
 * 外部导入重试的同名同内容判定与目录复用。
 *
 * <p>心跳超时恢复与手动重试会从远程重新拉取整份内容，没有这层判定就会把已入库的
 * 文件按 {@code name (1)} 再存一份。调用方只在“重入执行”时启用这些判定：首次导入
 * 是用户的显式意图，即便目标里已有同内容文件也必须新建副本。</p>
 *
 * @author OmniNest
 */
final class ExternalImportResumeDetector {

    private ExternalImportResumeDetector() {
    }

    /**
     * 查找目标目录中内容一致的既有文件。
     *
     * @param nodeRepository 文件节点仓储
     * @param objectRepository 文件对象仓储
     * @param task 导入任务，仅用于取所有者
     * @param spaceType 目标空间
     * @param parentId 目标父目录，null 表示空间根目录
     * @param fileName 源文件名
     * @param file 已下载到本地的文件
     * @return 可视为已导入的节点，不存在时为空
     */
    static Optional<FileNode> findAlreadyImported(
            FileNodeRepository nodeRepository,
            FileObjectRepository objectRepository,
            StorageImportTask task,
            SpaceType spaceType,
            UUID parentId,
            String fileName,
            Path file
    ) {
        Optional<FileNode> existing = ExternalImportNames.findByName(
                nodeRepository, task, spaceType, parentId, fileName);
        if (existing.isEmpty() || existing.get().getCurrentObjectId() == null) {
            return Optional.empty();
        }
        FileNode node = existing.get();
        String existingSha = objectRepository.findById(node.getCurrentObjectId())
                .map(FileObject::getSha256)
                .orElse(null);
        if (existingSha == null) {
            return Optional.empty();
        }
        return existingSha.equalsIgnoreCase(ExternalImportStreams.sha256Hex(file))
                ? Optional.of(node)
                : Optional.empty();
    }

    /**
     * 取回首次创建的导入根目录，供重试续跑复用。
     *
     * <p>目录重试若每次都新建根目录，已导入的文件会整份复制到“同名 (1)”目录下；
     * 根目录被用户删除或改成文件后回退为新建。</p>
     *
     * @param nodeRepository 文件节点仓储
     * @param task 导入任务
     * @param spaceType 目标空间
     * @return 可复用的根目录 ID
     */
    static Optional<UUID> reusableRoot(
            FileNodeRepository nodeRepository,
            StorageImportTask task,
            SpaceType spaceType
    ) {
        UUID rootId = task.getImportRootNodeId();
        if (rootId == null) {
            return legacyRoot(nodeRepository, task, spaceType);
        }
        Optional<FileNode> root = spaceType == SpaceType.SHARED
                ? nodeRepository.findByIdAndSpaceTypeAndDeletedFalse(rootId, SpaceType.SHARED)
                : nodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(rootId, task.getOwnerUserId());
        return root.filter(node -> NodeType.FOLDER.getValue().equals(node.getNodeType()))
                .map(FileNode::getId);
    }

    /**
     * 兜底定位旧任务的导入根目录：新增列之前的任务没有记录根目录 ID，
     * 按“同所有者/空间/父级/名称 + RCLONE 来源的文件夹”找回，避免重试再建一份。
     *
     * @param nodeRepository 文件节点仓储
     * @param task 导入任务
     * @param spaceType 目标空间
     * @return 可复用的根目录 ID
     */
    static Optional<UUID> legacyRoot(
            FileNodeRepository nodeRepository,
            StorageImportTask task,
            SpaceType spaceType
    ) {
        return ExternalImportNames.findByName(
                        nodeRepository, task, spaceType, task.getTargetParentId(), task.getFileName())
                .filter(node -> NodeType.FOLDER.getValue().equals(node.getNodeType()))
                .filter(node -> SourceType.RCLONE.getValue().equals(node.getSourceType()))
                .map(FileNode::getId);
    }

    /**
     * 重入时复用同名子目录：目录重试若逐层改名，已导入的文件会落进新建的空壳分支。
     *
     * @param nodeRepository 文件节点仓储
     * @param task 导入任务
     * @param spaceType 目标空间
     * @param parentId 父目录 ID
     * @param folderName 子目录名
     * @return 可复用的子目录 ID
     */
    static Optional<UUID> reusableFolder(
            FileNodeRepository nodeRepository,
            StorageImportTask task,
            SpaceType spaceType,
            UUID parentId,
            String folderName
    ) {
        return ExternalImportNames.findByName(nodeRepository, task, spaceType, parentId, folderName)
                .filter(node -> NodeType.FOLDER.getValue().equals(node.getNodeType()))
                .map(FileNode::getId);
    }
}
