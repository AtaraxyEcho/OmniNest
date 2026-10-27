package com.omninest.modules.file.service;

import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.domain.StorageImportTask;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import java.nio.file.Path;
import java.util.Optional;
import java.util.UUID;

/**
 * 外部导入重试的同名同内容判定。
 *
 * <p>心跳超时恢复与手动重试会从远程重新拉取整份内容，没有这层判定就会把已入库的
 * 文件按 {@code name (1)} 再存一份。先按名称命中才计算本地摘要，常态导入不会因此
 * 多读一遍文件；摘要不同仍走改名分支，避免误吞内容不同的同名文件。</p>
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
            return Optional.empty();
        }
        Optional<FileNode> root = spaceType == SpaceType.SHARED
                ? nodeRepository.findByIdAndSpaceTypeAndDeletedFalse(rootId, SpaceType.SHARED)
                : nodeRepository.findByIdAndOwnerUserIdAndDeletedFalse(rootId, task.getOwnerUserId());
        return root.filter(node -> NodeType.FOLDER.getValue().equals(node.getNodeType()))
                .map(FileNode::getId);
    }
}
