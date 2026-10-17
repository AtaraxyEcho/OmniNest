package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
import com.omninest.common.sync.SyncAction;
import com.omninest.common.sync.SyncEventCommand;
import com.omninest.common.sync.SyncScope;
import com.omninest.common.sync.UserSyncEventRecorder;
import com.omninest.modules.quota.service.StorageQuotaService;
import com.omninest.modules.file.domain.FileAccessRecord;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.domain.NodeType;
import com.omninest.modules.file.domain.SpaceType;
import com.omninest.modules.file.dto.FileNodeDto;
import com.omninest.modules.file.repository.FileAccessRecordRepository;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.time.Instant;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文件核心操作服务。
 * 负责最近访问、访问记录、节点复制与 ZIP 打包下载。
 * 收藏、分享、版本、外部存储与上传队列由对应的专项服务负责。
 *
 * @author OmniNest
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class FileManagerService {
    private final FileNodeRepository fileNodeRepository;
    private final FileAccessRecordRepository accessRecordRepository;
    private final FileObjectRepository fileObjectRepository;
    private final ObjectStorageClient objectStorageClient;
    private final FileNodeSupport fileNodeSupport;
    private final StorageQuotaService storageQuotaService;
    private final SharedSpaceQuotaService sharedSpaceQuotaService;
    private final UserSyncEventRecorder syncEventRecorder;

    /**
     * 查询用户最近访问的文件。
     *
     * @param ownerUserId 用户 ID
     * @return 最近访问文件列表
     */
    @Transactional(readOnly = true)
    public List<FileNodeDto> listRecentFiles(UUID ownerUserId) {
        List<FileNode> nodes = accessRecordRepository
                .findTop50ByOwnerUserIdOrderByLastAccessedAtDesc(ownerUserId)
                .stream()
                .map(FileAccessRecord::getFileNode)
                .filter(node -> node != null && !node.isDeleted() && node.getSpaceType() != SpaceType.SHARED)
                .toList();
        return fileNodeSupport.toNodeDtos(nodes);
    }

    /**
     * 记录文件访问。
     *
     * @param ownerUserId 用户 ID
     * @param fileId      文件节点 ID
     */
    @Transactional(rollbackFor = Exception.class)
    public void recordAccess(UUID ownerUserId, UUID fileId) {
        FileNode node = fileNodeSupport.findVisibleNode(ownerUserId, fileId);
        FileAccessRecord record = accessRecordRepository.findByOwnerUserIdAndFileNode_Id(ownerUserId, fileId)
                .orElseGet(() -> {
                    FileAccessRecord created = new FileAccessRecord();
                    created.setOwnerUserId(ownerUserId);
                    created.setFileNode(node);
                    return created;
                });
        record.setLastAccessedAt(Instant.now());
        record.setAccessCount(record.getAccessCount() + 1);
        accessRecordRepository.save(record);
    }

    /**
     * 复制文件或文件夹到目标位置。
     * 文件夹复制为浅复制（仅复制节点结构，不递归复制子文件）。
     *
     * @param userId         用户 ID
     * @param sourceId       源文件/文件夹 ID
     * @param targetParentId 目标父文件夹 ID，null 表示复制到根目录
     * @return 新创建的文件节点
     */
    @Transactional(rollbackFor = Exception.class)
    public FileNodeDto copyNode(UUID userId, UUID sourceId, UUID targetParentId) {
        FileNode source = fileNodeSupport.findActiveNode(userId, sourceId);
        fileNodeSupport.requireShareable(source);
        FileNode targetParent = fileNodeSupport.resolveCopyTargetParent(userId, targetParentId);
        UUID resolvedParentId = targetParent != null ? targetParent.getId() : null;

        // 校验源文件和目标在同一空间
        if (targetParent != null && source.getSpaceType() != targetParent.getSpaceType()) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "不能在不同空间之间复制文件");
        }
        if (fileNodeSupport.sameNameExists(userId, source.getSpaceType(), resolvedParentId, source.getName())) {
            throw new BusinessException(ErrorCode.CONFLICT, "目标目录下已存在同名文件");
        }

        FileNode copy = new FileNode();
        copy.setOwnerUserId(userId);
        copy.setParentId(resolvedParentId);
        copy.setNodeType(source.getNodeType());
        copy.setName(source.getName());
        copy.setNormalizedPath(fileNodeSupport.resolveChildPath(targetParent, source.getName()));
        copy.setMimeType(source.getMimeType());
        copy.setSizeBytes(source.getSizeBytes());
        copy.setCurrentObjectId(source.getCurrentObjectId());
        copy.setSpaceType(source.getSpaceType());
        if (source.getSpaceType() == SpaceType.SHARED) {
            copy.setUploadedBy(userId);
        }

        FileNode saved = fileNodeRepository.save(copy);
        // 副本按新节点计入配额：账本口径是节点数而非物理对象数，同一对象被两个节点引用
        // 时对账也计两次。不加计会让「复制后彻底删除副本」反向扣减，把已用空间刷空。
        chargeQuotaForCopy(userId, saved.getSpaceType(), saved.getSizeBytes());
        recordFileEvent(userId, saved.getId(), SyncAction.CREATED);
        log.info("文件复制完成: sourceId={}, copyId={}, ownerUserId={}", sourceId, saved.getId(), userId);
        return fileNodeSupport.toNodeDto(saved);
    }

    /**
     * 复制产生的新节点按所属空间结算配额，个人空间按用户、共享空间按全空间单行账本。
     */
    private void chargeQuotaForCopy(UUID userId, SpaceType spaceType, long bytes) {
        if (spaceType == SpaceType.SHARED) {
            sharedSpaceQuotaService.checkQuota(bytes);
            sharedSpaceQuotaService.increaseUsage(bytes, 1);
            return;
        }
        storageQuotaService.checkQuota(userId, bytes);
        storageQuotaService.incrementUsage(userId, bytes);
    }

    private void recordFileEvent(UUID ownerUserId, UUID fileId, SyncAction action) {
        syncEventRecorder.record(new SyncEventCommand(
                ownerUserId,
                SyncScope.FILES,
                "FILE_NODE",
                fileId.toString(),
                action,
                null,
                Map.of()
        ));
    }

    /**
     * 将多个文件打包为 ZIP 流式下载。
     * 跳过文件夹、回收站节点和无对象数据的文件；不同目录下的同名文件自动追加序号，
     * 因为 ZipOutputStream 遇到重名条目会直接抛错并截断已经在传输的响应流。
     *
     * @param userId  用户 ID
     * @param fileIds 要打包的文件 ID 列表
     * @param out     输出流
     */
    public void packAsZip(UUID userId, List<String> fileIds, OutputStream out) {
        Set<String> usedEntryNames = new HashSet<>();
        try (ZipOutputStream zip = new ZipOutputStream(out)) {
            for (String fileId : fileIds) {
                FileNode node = fileNodeRepository.findByIdAndOwnerUserId(UUID.fromString(fileId), userId)
                        .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在: " + fileId));
                // 回收站节点不得混入打包结果
                if (node.isDeleted()) {
                    continue;
                }
                // 跳过文件夹
                if (NodeType.FOLDER.getValue().equals(node.getNodeType())) {
                    continue;
                }
                // 无对象数据则跳过
                if (node.getCurrentObjectId() == null) {
                    continue;
                }
                FileObject obj = fileObjectRepository.findById(node.getCurrentObjectId()).orElse(null);
                if (obj == null) {
                    continue;
                }
                zip.putNextEntry(new ZipEntry(uniqueEntryName(node.getName(), usedEntryNames)));
                try (InputStream in = objectStorageClient.getObject(
                        new ObjectStorageKey(obj.getBucketName(), obj.getObjectKey()))) {
                    byte[] buffer = new byte[8192];
                    int len;
                    while ((len = in.read(buffer)) > 0) {
                        zip.write(buffer, 0, len);
                    }
                }
                zip.closeEntry();
            }
        } catch (IOException e) {
            log.error("ZIP 打包失败", e);
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "文件打包失败");
        }
    }

    /**
     * 生成 ZIP 内唯一的条目名：首个同名条目保持原名，后续追加 {@code (n)} 序号。
     *
     * <p>序号插在扩展名之前，保证解压后的文件仍能按原扩展名识别。</p>
     */
    private String uniqueEntryName(String proposedName, Set<String> usedNames) {
        String candidate = proposedName;
        int suffix = 1;
        while (!usedNames.add(candidate)) {
            candidate = appendSuffix(proposedName, suffix++);
        }
        return candidate;
    }

    private String appendSuffix(String name, int suffix) {
        int dot = name.lastIndexOf('.');
        if (dot <= 0) {
            return name + " (" + suffix + ")";
        }
        return name.substring(0, dot) + " (" + suffix + ")" + name.substring(dot);
    }
}
