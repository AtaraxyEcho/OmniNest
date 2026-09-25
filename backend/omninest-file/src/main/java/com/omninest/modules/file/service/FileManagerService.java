package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.common.storage.ObjectStorageClient;
import com.omninest.common.storage.ObjectStorageKey;
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
import java.util.List;
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

    /**
     * 查询用户最近访问的文件。
     *
     * @param ownerUserId 用户 ID
     * @return 最近访问文件列表
     */
    @Transactional(readOnly = true)
    public List<FileNodeDto> listRecentFiles(UUID ownerUserId) {
        return accessRecordRepository.findTop50ByOwnerUserIdOrderByLastAccessedAtDesc(ownerUserId)
                .stream()
                .map(FileAccessRecord::getFileNode)
                .filter(node -> node != null && !node.isDeleted() && node.getSpaceType() != SpaceType.SHARED)
                .map(fileNodeSupport::toNodeDto)
                .toList();
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
        if (fileNodeSupport.sameNameExists(userId, resolvedParentId, source.getName())) {
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
        log.info("文件复制完成: sourceId={}, copyId={}, ownerUserId={}", sourceId, saved.getId(), userId);
        return fileNodeSupport.toNodeDto(saved);
    }

    /**
     * 将多个文件打包为 ZIP 流式下载。
     * 跳过文件夹节点和无对象数据的文件。
     *
     * @param userId  用户 ID
     * @param fileIds 要打包的文件 ID 列表
     * @param out     输出流
     */
    public void packAsZip(UUID userId, List<String> fileIds, OutputStream out) {
        try (ZipOutputStream zip = new ZipOutputStream(out)) {
            for (String fileId : fileIds) {
                FileNode node = fileNodeRepository.findByIdAndOwnerUserId(UUID.fromString(fileId), userId)
                        .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在: " + fileId));
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
                zip.putNextEntry(new ZipEntry(node.getName()));
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
}
