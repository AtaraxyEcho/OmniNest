package com.omninest.modules.file.service;

import com.omninest.common.enums.ErrorCode;
import com.omninest.common.error.BusinessException;
import com.omninest.modules.file.domain.FileNode;
import com.omninest.modules.file.domain.FileObject;
import com.omninest.modules.file.domain.FileVersion;
import com.omninest.modules.file.dto.FileNodeDto;
import com.omninest.modules.file.dto.FileVersionDto;
import com.omninest.modules.file.repository.FileNodeRepository;
import com.omninest.modules.file.repository.FileObjectRepository;
import com.omninest.modules.file.repository.FileUploadSessionRepository;
import com.omninest.modules.file.repository.FileVersionRepository;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 文件版本服务。
 * 负责历史版本保存、查询与恢复。
 *
 * @author OmniNest
 */
@Service
@RequiredArgsConstructor
public class FileVersionService {
    private final FileNodeRepository fileNodeRepository;
    private final FileObjectRepository fileObjectRepository;
    private final FileVersionRepository fileVersionRepository;
    private final FileUploadSessionRepository uploadSessionRepository;
    private final FileContentChangePublisher fileContentChangePublisher;
    private final FileNodeSupport fileNodeSupport;
    private final FileSyncEventWriter syncEventWriter;

    /**
     * 将文件当前对象保存为历史版本，并把已上传的新对象设为当前对象。
     *
     * @param ownerUserId         文件所有者
     * @param fileNodeId          文件节点 ID
     * @param newObjectId         新对象 ID（已持久化）
     * @param newObjectSizeBytes  新对象大小（字节）
     * @param remark              版本备注，可空
     * @return 文件节点最新状态
     */
    @Transactional(rollbackFor = Exception.class)
    public FileNodeDto saveNewVersion(
            UUID ownerUserId,
            UUID fileNodeId,
            UUID newObjectId,
            long newObjectSizeBytes,
            String remark
    ) {
        FileNode node = fileNodeRepository
                .findOwnedForUpdate(fileNodeId, ownerUserId)
                .filter(existing -> !existing.isDeleted())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        // LOCAL 只读来源无版本写语义，与 restoreVersion / 分享复制同一守卫。
        fileNodeSupport.requireShareable(node);
        if (node.getCurrentObjectId() == null) {
            throw new BusinessException(ErrorCode.VALIDATION_FAILED, "该文件没有可版本化的当前内容");
        }
        FileObject newObject = fileObjectRepository.findById(newObjectId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "文件对象不存在"));
        if (!isObjectOwnedByUser(newObject, ownerUserId)) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "文件对象不属于当前用户");
        }
        rejectObjectAliasedToOtherNode(ownerUserId, fileNodeId, newObject.getId());
        // 入口晋升的 asVersion 对象已落到 users/{uid}/...，会话结果可能尚未回写；
        // 仅对仍处于 uploads/ 暂存前缀的对象强制「必须来自本次上传会话」。
        String newObjectKey = newObject.getObjectKey() == null ? "" : newObject.getObjectKey();
        if (newObjectKey.startsWith("uploads/")
                && uploadSessionRepository
                        .findFirstByOwnerUserIdAndResultObjectId(ownerUserId, newObjectId)
                        .isEmpty()) {
            throw new BusinessException(ErrorCode.FORBIDDEN, "文件对象必须来自本次上传会话");
        }
        if (newObjectSizeBytes > 0 && newObjectSizeBytes != newObject.getSizeBytes()) {
            throw new BusinessException(ErrorCode.VALIDATION_FAILED, "文件对象大小与声明不一致");
        }
        int nextVersionNo = fileVersionRepository.findMaxVersionNo(fileNodeId) + 1;
        FileVersion version = new FileVersion();
        version.setFileNodeId(fileNodeId);
        version.setObjectId(node.getCurrentObjectId());
        version.setVersionNo(nextVersionNo);
        version.setChangeType("EDIT");
        version.setCreatedBy(ownerUserId);
        version.setRemark(remark);
        fileVersionRepository.save(version);

        node.setCurrentObjectId(newObject.getId());
        node.setSizeBytes(newObject.getSizeBytes());
        if (newObject.getMimeType() != null && !newObject.getMimeType().isBlank()) {
            node.setMimeType(newObject.getMimeType());
        }
        node.setUpdatedAt(Instant.now());
        FileNode saved = fileNodeRepository.save(node);
        fileContentChangePublisher.publish(saved, newObject, ownerUserId);
        syncEventWriter.recordFileEvent(ownerUserId, fileNodeId, Map.of("version", nextVersionNo));
        return fileNodeSupport.toNodeDto(saved);
    }

    /**
     * 查询文件版本历史（新版本在前），当前对象补充为一条 CURRENT 条目。
     *
     * @param ownerUserId 文件所有者
     * @param fileNodeId  文件节点 ID
     * @return 版本条目列表
     */
    @Transactional(readOnly = true)
    public List<FileVersionDto> listVersions(UUID ownerUserId, UUID fileNodeId) {
        FileNode node = fileNodeSupport.findActiveNode(ownerUserId, fileNodeId);
        List<FileVersion> versions = fileVersionRepository.findByFileNodeIdOrderByVersionNoDesc(fileNodeId);
        List<FileVersionDto> items = new ArrayList<>();
        for (FileVersion version : versions) {
            FileObject object = fileObjectRepository.findById(version.getObjectId()).orElse(null);
            items.add(new FileVersionDto(
                    version.getId(),
                    version.getVersionNo(),
                    version.getObjectId(),
                    version.getChangeType(),
                    object == null ? 0L : object.getSizeBytes(),
                    version.getCreatedBy(),
                    version.getCreatedAt(),
                    version.getObjectId().equals(node.getCurrentObjectId()),
                    version.getRemark()
            ));
        }
        if (node.getCurrentObjectId() != null
                && versions.stream().noneMatch(v -> v.getObjectId().equals(node.getCurrentObjectId()))) {
            FileObject current = fileObjectRepository.findById(node.getCurrentObjectId()).orElse(null);
            if (current != null) {
                items.add(0, new FileVersionDto(
                        null,
                        versions.isEmpty() ? 1 : versions.get(0).getVersionNo() + 1,
                        current.getId(),
                        "CURRENT",
                        current.getSizeBytes(),
                        node.getOwnerUserId(),
                        current.getCreatedAt(),
                        true,
                        null
                ));
            }
        }
        return List.copyOf(items);
    }

    /**
     * 恢复历史版本：把恢复前的当前对象存为 RESTORE 版本行，再把历史版本对象设为当前对象。
     *
     * @param ownerUserId 文件所有者
     * @param fileNodeId  文件节点 ID
     * @param versionId   版本行 ID
     * @return 文件节点最新状态
     */
    @Transactional(rollbackFor = Exception.class)
    public FileNodeDto restoreVersion(UUID ownerUserId, UUID fileNodeId, UUID versionId) {
        FileNode node = fileNodeRepository
                .findOwnedForUpdate(fileNodeId, ownerUserId)
                .filter(existing -> !existing.isDeleted())
                .orElseThrow(() -> new BusinessException(ErrorCode.FILE_NOT_FOUND, "文件不存在"));
        fileNodeSupport.requireShareable(node);
        FileVersion version = fileVersionRepository.findById(versionId)
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "版本不存在"));
        if (!version.getFileNodeId().equals(fileNodeId)) {
            throw new BusinessException(ErrorCode.VALIDATION_FAILED, "版本与文件不匹配");
        }
        if (version.getObjectId().equals(node.getCurrentObjectId())) {
            return fileNodeSupport.toNodeDto(node);
        }
        if (node.getCurrentObjectId() == null) {
            throw new BusinessException(ErrorCode.VALIDATION_FAILED, "当前文件没有可备份的内容，无法恢复历史版本");
        }
        int nextVersionNo = fileVersionRepository.findMaxVersionNo(fileNodeId) + 1;
        FileVersion history = new FileVersion();
        history.setFileNodeId(fileNodeId);
        history.setObjectId(node.getCurrentObjectId());
        history.setVersionNo(nextVersionNo);
        history.setChangeType("RESTORE");
        history.setCreatedBy(ownerUserId);
        fileVersionRepository.save(history);

        FileObject restoredObject = fileObjectRepository.findById(version.getObjectId())
                .orElseThrow(() -> new BusinessException(ErrorCode.NOT_FOUND, "版本对象不存在"));
        node.setCurrentObjectId(restoredObject.getId());
        node.setSizeBytes(restoredObject.getSizeBytes());
        if (restoredObject.getMimeType() != null && !restoredObject.getMimeType().isBlank()) {
            node.setMimeType(restoredObject.getMimeType());
        }
        node.setUpdatedAt(Instant.now());
        FileNode saved = fileNodeRepository.save(node);
        fileContentChangePublisher.publish(saved, restoredObject, ownerUserId);
        syncEventWriter.recordFileEvent(ownerUserId, fileNodeId, Map.of("restoredTo", version.getVersionNo()));
        return fileNodeSupport.toNodeDto(saved);
    }

    private void rejectObjectAliasedToOtherNode(UUID ownerUserId, UUID fileNodeId, UUID objectId) {
        fileNodeRepository.findActiveByOwnerUserIdAndObjectId(ownerUserId, objectId)
                .filter(existing -> !existing.getId().equals(fileNodeId))
                .ifPresent(existing -> {
                    throw new BusinessException(ErrorCode.FORBIDDEN, "文件对象已被其他文件使用");
                });
    }

    private boolean isObjectOwnedByUser(FileObject object, UUID ownerUserId) {
        String objectKey = object.getObjectKey();
        if (objectKey == null || objectKey.isBlank()) {
            return false;
        }
        // 直传暂存键与晋升后的用户受管键均表示归属该用户。
        return objectKey.startsWith("uploads/" + ownerUserId + "/")
                || objectKey.startsWith("users/" + ownerUserId + "/");
    }
}
